#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/pack_release.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p561_${TS}"
echo "[OK] backup => ${F}.bak_p561_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/pack_release.sh")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P561_PACK_RELEASE_GATED_AND_CLEAN_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

insert = r'''
# --- VSP_P561_PACK_RELEASE_GATED_AND_CLEAN_V1 ---
# Must gate by P550 before packaging FINAL
if [ -x "bin/p550_gate_run_to_report_v1d.sh" ]; then
  echo "== [P561] run P550 gate =="
  bash bin/p550_gate_run_to_report_v1d.sh
  p550_latest="$(ls -1dt out_ci/p550_* 2>/dev/null | head -n1 || true)"
  if [ -z "$p550_latest" ] || [ ! -f "$p550_latest/RESULT.txt" ]; then
    echo "[FAIL] P550 RESULT.txt missing"; exit 9
  fi
  if ! grep -q "^PASS" "$p550_latest/RESULT.txt"; then
    echo "[FAIL] P550 not PASS: $p550_latest/RESULT.txt"; exit 9
  fi
  echo "[OK] P550 PASS => continue packaging"
else
  echo "[WARN] missing bin/p550_gate_run_to_report_v1d.sh (should exist for commercial)"
fi

# Excludes for commercial ship hygiene
EXCLUDES=(
  "--exclude=bin/p*"
  "--exclude=bin/legacy"
  "--exclude=out_ci"
  "--exclude=*.bak_*"
  "--exclude=__pycache__"
  "--exclude=.pytest_cache"
  "--exclude=.mypy_cache"
  "--exclude=node_modules"
)

# Try to pull latest HTML/PDF into release dir (best-effort)
copy_reports_into_release_dir(){
  local rel_dir="$1"
  # Prefer run_dir from latest RID via run_status_v1 if BASE available
  local base="${VSP_UI_BASE:-http://127.0.0.1:8910}"
  local rid run_dir
  rid="$(curl -fsS --connect-timeout 2 --max-time 8 "$base/api/ui/runs_v3?limit=1&include_ci=1" \
    | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("items",[{}])[0].get("rid",""))' 2>/dev/null || true)"
  if [ -n "$rid" ]; then
    run_dir="$(curl -fsS --connect-timeout 2 --max-time 8 "$base/api/vsp/run_status_v1/$rid" \
      | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("run_dir",""))' 2>/dev/null || true)"
    if [ -n "$run_dir" ] && [ -d "$run_dir" ]; then
      for f in "$run_dir"/reports/*.html "$run_dir"/reports/*.pdf; do
        [ -f "$f" ] || continue
        cp -f "$f" "$rel_dir/" || true
      done
    fi
  fi
}

# --- end VSP_P561_PACK_RELEASE_GATED_AND_CLEAN_V1 ---
'''.lstrip("\n")

# Heuristic: place insert right before tar creation (first "tar " occurrence)
m = re.search(r'^\s*tar\s', s, flags=re.M)
if not m:
    # fallback: append near end
    s2 = s.rstrip() + "\n\n" + insert + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched (append fallback)")
    raise SystemExit(0)

pos = m.start()
s2 = s[:pos] + insert + s[pos:]

# Now ensure tar uses EXCLUDES if it's a simple tar line; we patch first tar -czf
def patch_tar(cmd: str) -> str:
    if "EXCLUDES" in cmd:
        return cmd
    # Inject "${EXCLUDES[@]}" after tar
    return re.sub(r'^\s*tar(\s+)', r'tar \1"${EXCLUDES[@]}" ', cmd, count=1)

lines = s2.splitlines(True)
out=[]
patched=False
for line in lines:
    if not patched and re.match(r'^\s*tar\s+.*-czf', line):
        out.append(patch_tar(line))
        patched=True
    else:
        out.append(line)

p.write_text("".join(out), encoding="utf-8")
print("[OK] patched tar excludes + P550 gate + report copy helper")
PY

bash -n bin/pack_release.sh
echo "[OK] bash -n pack_release.sh"
