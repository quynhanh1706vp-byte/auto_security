#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p577_${TS}"
echo "[OK] backup => ${F}.bak_p577_${TS}"

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
# --- P577_TAR_MEMBER_TEST_V1 ---
code_tgz="$(ls -1 "$latest_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$code_tgz" ] || { echo "[FAIL] missing VSP_UI_*.tgz in $latest_dir"; exit 5; }
[ -f "$code_tgz" ] || { echo "[FAIL] VSP_UI tgz not found: $code_tgz"; exit 5; }

has_member(){
  local want="$1"
  tar -tzf "$code_tgz" "$want" >/dev/null 2>&1 && return 0
  tar -tzf "$code_tgz" "./$want" >/dev/null 2>&1 && return 0
  return 1
}

required=(
  "config/systemd_unit.template"
  "config/logrotate_vsp-ui.template"
  "config/production.env.example"
  "RELEASE_NOTES.md"
  "bin/ui_gate.sh"
  "bin/verify_release_and_customer_smoke.sh"
  "bin/pack_release.sh"
  "bin/ops.sh"
)

missing=()
for r in "${required[@]}"; do
  has_member "$r" || missing+=("$r")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING_IN_CODE_TGZ:${missing[*]}"
  echo "[DBG] code_tgz=$code_tgz"
  echo "[DBG] show relevant entries (bin/config/notes):"
  tar -tzf "$code_tgz" | egrep '(^|^\./)(bin/(ui_gate|verify_release_and_customer_smoke|pack_release|ops)\.sh$|config/|RELEASE_NOTES\.md$)' | head -n 120 || true
  exit 5
fi

log "[OK] contract inside code tgz PASS: $(basename "$code_tgz")"
exit 0
# --- END P577_TAR_MEMBER_TEST_V1 ---
# --- END P570_CHECK_INSIDE_CODE_TGZ ---'''

s2 = s[:i] + new_block + s[j_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced P570 block with P577 tar-member test")
PY

bash -n "$F"
echo "[OK] bash -n ok"

bash bin/verify_release_and_customer_smoke.sh
