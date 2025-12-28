#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
UI="/home/test/Data/SECURITY_BUNDLE/ui"
BIN="$ROOT/bin"
PY="$BIN/ensure_min_reports_v2.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need sed; need grep; need find

[ -d "$ROOT" ] || { echo "[ERR] missing $ROOT"; exit 2; }
mkdir -p "$BIN"

TS="$(date +%Y%m%d_%H%M%S)"
if [ -f "$PY" ]; then
  cp -f "$PY" "$PY.bak_${TS}"
  echo "[BACKUP] $PY.bak_${TS}"
fi

cat > "$PY" <<'PY'
#!/usr/bin/env python3
# ensure_min_reports_v2.py
import json, os, sys, hashlib
from pathlib import Path
from datetime import datetime

MARK = "ENSURE_MIN_REPORTS_V2"

def sha256_file(p: Path) -> str:
    h=hashlib.sha256()
    with p.open("rb") as f:
        for ch in iter(lambda: f.read(1024*1024), b""):
            h.update(ch)
    return h.hexdigest()

def best_effort_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

def write_json(p: Path, obj):
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def main():
    if len(sys.argv) < 2:
        print("[ERR] usage: ensure_min_reports_v2.py <RUN_DIR>", file=sys.stderr)
        return 2
    run_dir = Path(sys.argv[1]).resolve()
    if not run_dir.exists():
        print(f"[ERR] run_dir not found: {run_dir}", file=sys.stderr)
        return 2

    reports = run_dir / "reports"
    reports.mkdir(parents=True, exist_ok=True)

    # Locate likely sources
    src_summary_txt = (run_dir / "SUMMARY.txt")
    src_gate_json = (run_dir / "run_gate.json")
    src_gate_sum = (reports / "run_gate_summary.json")
    src_findings = None
    for cand in [
        run_dir / "findings_unified.json",
        reports / "findings_unified.json",
        run_dir / "reports" / "findings_unified.json",
        run_dir / "findings.json",
    ]:
        if cand.exists():
            src_findings = cand
            break

    # (1) SUMMARY.txt -> reports/SUMMARY.txt
    out_summary = reports / "SUMMARY.txt"
    if not out_summary.exists():
        if src_summary_txt.exists():
            out_summary.write_text(src_summary_txt.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        else:
            # generate minimal summary
            gate = best_effort_json(src_gate_json) or {}
            now = datetime.utcnow().isoformat() + "Z"
            lines = [
                f"{MARK}",
                f"run_dir={run_dir}",
                f"generated_at={now}",
            ]
            if gate:
                lines.append("run_gate.json: present")
                verdict = gate.get("overall") or gate.get("verdict") or gate.get("gate") or ""
                if verdict:
                    lines.append(f"overall={verdict}")
            out_summary.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # (2) findings_unified.json -> reports/findings_unified.json
    out_findings = reports / "findings_unified.json"
    if not out_findings.exists():
        if src_findings and src_findings.exists():
            out_findings.write_text(src_findings.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        else:
            # create empty structure (still valid file)
            write_json(out_findings, {"items": [], "note": "generated empty findings_unified.json"})

    # (3) run_gate_summary.json (minimal) in reports/
    if not src_gate_sum.exists():
        gate = best_effort_json(src_gate_json) or {}
        # derive counts if possible
        summary = {
            "ok": True,
            "generated_by": MARK,
            "run_dir": str(run_dir),
            "overall": gate.get("overall") or gate.get("verdict") or gate.get("gate") or "UNKNOWN",
            "has": {
                "index_html": (reports / "index.html").exists(),
                "summary_txt": out_summary.exists(),
                "findings_unified_json": out_findings.exists(),
            },
        }
        write_json(src_gate_sum, summary)

    # (4) reports/index.html minimal landing
    out_index = reports / "index.html"
    if not out_index.exists():
        rid = run_dir.name
        # prefer linking to relative files in the same folder
        html = f"""<!doctype html>
<html><head><meta charset="utf-8">
<title>VSP Report - {rid}</title>
<style>
body{{font-family:system-ui,Arial,sans-serif; padding:16px;}}
a{{display:block; padding:6px 0;}}
code{{background:#eee; padding:2px 6px; border-radius:6px;}}
.small{{opacity:.8; font-size:12px;}}
</style>
</head>
<body>
<h2>VSP Report</h2>
<div class="small">generated_by <code>{MARK}</code></div>
<p><b>RID:</b> <code>{rid}</code></p>
<ul>
  <li><a href="run_gate_summary.json">run_gate_summary.json</a></li>
  <li><a href="findings_unified.json">findings_unified.json</a></li>
  <li><a href="SUMMARY.txt">SUMMARY.txt</a></li>
</ul>
</body></html>
"""
        out_index.write_text(html, encoding="utf-8")

    # Optional: write sha file for these 4 key artifacts
    sha_out = reports / "SHA256SUMS.txt"
    try:
        keys = ["index.html", "run_gate_summary.json", "findings_unified.json", "SUMMARY.txt"]
        lines=[]
        for fn in keys:
            p = reports / fn
            if p.exists():
                lines.append(f"{sha256_file(p)}  {fn}")
        sha_out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    except Exception:
        pass

    print("[OK] ensure_min_reports_v2:", run_dir)
    print(" -", out_index)
    print(" -", src_gate_sum)
    print(" -", out_findings)
    print(" -", out_summary)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
PY

chmod +x "$PY"
echo "[OK] wrote $PY"

# Hook into runner after unify (best-effort)
echo "== hook runner after unify (best-effort) =="
cands=()
while IFS= read -r -d '' f; do cands+=("$f"); done < <(find "$ROOT/bin" -maxdepth 2 -type f -name "*.sh" -print0)

patched=0
for f in "${cands[@]}"; do
  # only patch likely orchestrators
  if ! grep -qE 'run_all|all_tools|unify' "$f"; then
    continue
  fi
  if grep -q "ENSURE_MIN_REPORTS_V2_HOOKED_V1" "$f"; then
    continue
  fi

  # If file calls unify.sh or vsp_unify, inject after that line
  if grep -qE 'unify\.sh|vsp_unify|unify_findings|findings_unified' "$f"; then
    cp -f "$f" "$f.bak_ensuremin_${TS}"
    echo "[BACKUP] $f.bak_ensuremin_${TS}"

    python3 - <<PY2
from pathlib import Path
import re
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="ENSURE_MIN_REPORTS_V2_HOOKED_V1"
if MARK in s:
    print("[SKIP] already:", p); raise SystemExit(0)

hook = r'''
# ENSURE_MIN_REPORTS_V2_HOOKED_V1
if [ -n "${RUN_DIR:-}" ] && [ -d "${RUN_DIR:-}" ]; then
  python3 /home/test/Data/SECURITY_BUNDLE/bin/ensure_min_reports_v2.py "$RUN_DIR" || true
fi
'''.strip()+"\n"

# insert after the first unify invocation
pat = re.compile(r'^(.*(?:unify\.sh|vsp_unify|unify_findings).*)$', re.M)
m = pat.search(s)
if not m:
    # fallback: append at end
    s = s.rstrip()+"\n\n"+hook
else:
    end = m.end()
    s = s[:end] + "\n" + hook + s[end:]

p.write_text(s, encoding="utf-8")
print("[OK] hooked:", p)
PY2
    patched=$((patched+1))
  fi
done

echo "[OK] runner files hooked = $patched"
echo "[NEXT] run a fresh scan once; new RUN should always have 4 files in reports/"
