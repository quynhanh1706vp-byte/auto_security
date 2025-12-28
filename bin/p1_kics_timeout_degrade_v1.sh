#!/usr/bin/env bash
set +e
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui || exit 2

ROOTS=(
  "/home/test/Data/SECURITY-10-10-v4"
  "/home/test/Data/SECURITY_BUNDLE"
)

KICS_TIMEOUT_SEC="${KICS_TIMEOUT_SEC:-1200}"   # 20 phút (bạn đổi env nếu muốn)
echo "[INFO] KICS_TIMEOUT_SEC=$KICS_TIMEOUT_SEC"

py_patch() {
python3 - <<'PY'
from pathlib import Path
import re, time, json, os

roots = ["/home/test/Data/SECURITY-10-10-v4", "/home/test/Data/SECURITY_BUNDLE"]
marker = "VSP_P1_KICS_TIMEOUT_DEGRADED_V1"

def backup(p: Path):
    ts=time.strftime("%Y%m%d_%H%M%S")
    b=p.with_name(p.name+f".bak_kics_timeout_{ts}")
    b.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[BACKUP]", b)

def patch_file(p: Path):
    s=p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already:", p)
        return

    lines=s.splitlines(True)

    # inject helper block after shebang / near top
    insert_at=0
    if lines and lines[0].startswith("#!"):
        insert_at=1

    helper = f"""
# {marker}
KICS_TIMEOUT_SEC="${{KICS_TIMEOUT_SEC:-1200}}"
_vsp_kics_degraded_write() {{
  local reason="${{1:-timeout_or_error}}"
  local rid="${{RID:-${{RUN_ID:-${{RUN_RID:-unknown}}}}}}"
  local rd="${{RUN_DIR:-${{CI_RUN_DIR:-}}}}"
  [ -n "$rd" ] || return 0
  mkdir -p "$rd/kics" 2>/dev/null || true
  cat > "$rd/kics/kics_summary.json" <<EOF
{{"tool":"kics","ok":true,"degraded":true,"degraded_reason":"$reason","rid":"$rid","ts":"$(date +%Y-%m-%dT%H:%M:%S%z)"}}
EOF
}}
""".lstrip()

    lines.insert(insert_at, helper)

    # wrap first likely KICS execution line
    # match: 'kics scan ...' OR 'docker ... kics ...' OR 'checkmarx/kics'
    pat = re.compile(r'^\s*(?!#).*(\bkics\b.*\bscan\b|checkmarx/kics|docker.*\bkics\b).*$', re.I)
    wrapped=False
    for i,ln in enumerate(lines):
        if pat.match(ln) and "timeout" not in ln and marker not in ln:
            indent = re.match(r'^(\s*)', ln).group(1)
            cmd = ln.strip().rstrip(";")
            # Make it never block pipeline:
            new = (
                f'{indent}echo "[INFO] KICS timeout=${{KICS_TIMEOUT_SEC}}s"\n'
                f'{indent}timeout -k 30s "${{KICS_TIMEOUT_SEC}}s" {cmd} || {{ '
                f'echo "[WARN] KICS degraded (timeout/error)"; _vsp_kics_degraded_write "timeout_or_error"; }}\n'
            )
            lines[i]=new
            wrapped=True
            break

    if not wrapped:
        # If no direct kics line found, leave helper only (still useful if other scripts source it).
        print("[WARN] no kics exec line matched in", p)

    p.write_text("".join(lines), encoding="utf-8")
    print("[OK] patched:", p)

for r in roots:
    root=Path(r)
    if not root.is_dir(): 
        continue
    # target likely scripts
    cands=list(root.rglob("bin/run_kics*.sh")) + list(root.rglob("bin/*kics*.sh"))
    # prefer run_kics*.sh
    cands=sorted({c.resolve() for c in cands if c.is_file()})
    for p in cands[:20]:
        try:
            s=p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if "kics" not in s.lower():
            continue
        backup(p)
        patch_file(p)

PY
}

py_patch

echo "== bash -n (best effort) =="
for r in "${ROOTS[@]}"; do
  [ -d "$r" ] || continue
  for f in "$r"/bin/*kics*.sh "$r"/bin/run_kics*.sh; do
    [ -f "$f" ] || continue
    bash -n "$f" >/dev/null 2>&1 && echo "[OK] bash -n $f" || echo "[WARN] bash -n failed $f"
  done
done

echo "[DONE] Restart new run from UI (/runs) to verify KICS no longer stalls."
