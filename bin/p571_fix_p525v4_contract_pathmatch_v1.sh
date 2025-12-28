#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p571_${TS}"
echo "[OK] backup => ${F}.bak_p571_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/legacy/p525_verify_release_and_customer_smoke_v4.sh")
s = p.read_text(encoding="utf-8", errors="replace")

# Replace the strict grep -qx "$r" check with a helper that matches both "r" and "./r"
marker = "P571_PATHMATCH_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the P570 injected block area by locating required_inside=
m = re.search(r'required_inside=\(\s*\n(?:.|\n)*?\n\)\n\nmissing_inside=\(\)\n(?:.|\n)*?for r in "\$\{required_inside\[@\]\}"; do\n(?:.|\n)*?done\n', s)
if not m:
    print("[ERR] cannot locate required_inside block to patch")
    raise SystemExit(2)

block = m.group(0)

# Build a safer block: tar list once, then match both forms
new_block = r'''required_inside=(
  "config/systemd_unit.template"
  "config/logrotate_vsp-ui.template"
  "config/production.env.example"
  "RELEASE_NOTES.md"
  "bin/ui_gate.sh"
  "bin/verify_release_and_customer_smoke.sh"
  "bin/pack_release.sh"
  "bin/ops.sh"
)

# --- P571_PATHMATCH_V1 ---
tar_list="$(tar -tzf "$code_tgz")"

has_in_tgz(){
  local r="$1"
  echo "$tar_list" | grep -qx "$r" && return 0
  echo "$tar_list" | grep -qx "./$r" && return 0
  return 1
}

missing_inside=()
for r in "${required_inside[@]}"; do
  if ! has_in_tgz "$r"; then
    missing_inside+=("$r")
  fi
done
# --- END P571_PATHMATCH_V1 ---
'''

# Replace old block with new_block (keep surrounding content)
s2 = s[:m.start()] + new_block + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] patched v4 contract path matching")
PY

bash -n "$F"
echo "[OK] bash -n ok"

# run verify again
bash bin/verify_release_and_customer_smoke.sh
