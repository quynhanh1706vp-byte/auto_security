#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p574b_${TS}"
echo "[OK] backup => ${F}.bak_p574b_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/legacy/p525_verify_release_and_customer_smoke_v4.sh")
s = p.read_text(encoding="utf-8", errors="replace")

start_tag = "# --- P570_CHECK_INSIDE_CODE_TGZ ---"
end_tag   = "# --- END P570_CHECK_INSIDE_CODE_TGZ ---"

i = s.find(start_tag)
j = s.find(end_tag)

if i < 0 or j < 0 or j <= i:
    raise SystemExit("[ERR] cannot find P570 marker block to replace (start/end tags missing)")

j_end = j + len(end_tag)

new_block = r'''# --- P570_CHECK_INSIDE_CODE_TGZ ---
# --- P574_CONTRACT_REGEX_V1 ---
code_tgz="$(ls -1 "$latest_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$code_tgz" ] || { echo "[FAIL] missing VSP_UI_*.tgz in $latest_dir"; exit 5; }

tar_list="$(tar -tzf "$code_tgz")"

missing=()

# config templates + notes (match both ./path and path)
echo "$tar_list" | grep -Eq '^(\./)?config/systemd_unit\.template$'     || missing+=("config/systemd_unit.template")
echo "$tar_list" | grep -Eq '^(\./)?config/logrotate_vsp-ui\.template$' || missing+=("config/logrotate_vsp-ui.template")
echo "$tar_list" | grep -Eq '^(\./)?config/production\.env\.example$'   || missing+=("config/production.env.example")
echo "$tar_list" | grep -Eq '^(\./)?RELEASE_NOTES\.md$'                 || missing+=("RELEASE_NOTES.md")

# 4 entrypoints
echo "$tar_list" | grep -Eq '^(\./)?bin/ui_gate\.sh$'                         || missing+=("bin/ui_gate.sh")
echo "$tar_list" | grep -Eq '^(\./)?bin/verify_release_and_customer_smoke\.sh$' || missing+=("bin/verify_release_and_customer_smoke.sh")
echo "$tar_list" | grep -Eq '^(\./)?bin/pack_release\.sh$'                    || missing+=("bin/pack_release.sh")
echo "$tar_list" | grep -Eq '^(\./)?bin/ops\.sh$'                             || missing+=("bin/ops.sh")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING_IN_CODE_TGZ:${missing[*]}"
  exit 5
fi

log "[OK] contract inside code tgz PASS: $(basename "$code_tgz")"
exit 0
# --- END P574_CONTRACT_REGEX_V1 ---
# --- END P570_CHECK_INSIDE_CODE_TGZ ---'''

s2 = s[:i] + new_block + s[j_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced P570 block with P574 regex matcher")
PY

bash -n "$F"
echo "[OK] bash -n ok"

# run verify again
bash bin/verify_release_and_customer_smoke.sh
