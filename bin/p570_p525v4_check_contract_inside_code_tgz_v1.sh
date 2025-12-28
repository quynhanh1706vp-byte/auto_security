#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p570_${TS}"
echo "[OK] backup => ${F}.bak_p570_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("bin/legacy/p525_verify_release_and_customer_smoke_v4.sh")
s=p.read_text(encoding="utf-8", errors="replace")

if "P570_CHECK_INSIDE_CODE_TGZ" in s:
    print("[OK] already patched")
    raise SystemExit(0)

needle = r'log "\=\= \[3\] contract check \(NEW commercial\) \=\="'
m=re.search(needle, s)
if not m:
    print("[ERR] cannot find contract section")
    raise SystemExit(2)

insert = r'''
log "== [3] contract check (NEW commercial) =="
# --- P570_CHECK_INSIDE_CODE_TGZ ---
code_tgz="$(ls -1 "$latest_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$code_tgz" ] || { echo "[FAIL] missing VSP_UI_*.tgz in $latest_dir"; exit 5; }

# Must exist INSIDE code tgz (not only workspace)
required_inside=(
  "./config/systemd_unit.template"
  "./config/logrotate_vsp-ui.template"
  "./config/production.env.example"
  "./RELEASE_NOTES.md"
  "./bin/ui_gate.sh"
  "./bin/verify_release_and_customer_smoke.sh"
  "./bin/pack_release.sh"
  "./bin/ops.sh"
)

missing_inside=()
for r in "${required_inside[@]}"; do
  if ! tar -tzf "$code_tgz" | grep -qx "$r"; then
    missing_inside+=("$r")
  fi
done

if [ "${#missing_inside[@]}" -gt 0 ]; then
  echo "MISSING_IN_CODE_TGZ:${missing_inside[*]}"
  exit 5
fi

log "[OK] contract inside code tgz PASS: $(basename "$code_tgz")"
exit 0
# --- END P570_CHECK_INSIDE_CODE_TGZ ---
'''
# Replace old workspace-based check block by inserting and short-circuiting.
# We insert right after the contract section log line and before any existing "missing=()" logic.
s = re.sub(needle + r'.*?\nmissing=\(\)\n', needle + "\n" + insert + "\n", s, flags=re.S)

p.write_text(s, encoding="utf-8")
print("[OK] patched v4 to check inside code tgz")
PY

bash -n "$F"
echo "[OK] bash -n ok"

bash bin/verify_release_and_customer_smoke.sh
