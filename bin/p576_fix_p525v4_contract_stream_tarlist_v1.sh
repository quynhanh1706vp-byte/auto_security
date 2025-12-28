#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p576_${TS}"
echo "[OK] backup => ${F}.bak_p576_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("bin/legacy/p525_verify_release_and_customer_smoke_v4.sh")
s = p.read_text(encoding="utf-8", errors="replace")

start_tag = "# --- P570_CHECK_INSIDE_CODE_TGZ ---"
end_tag   = "# --- END P570_CHECK_INSIDE_CODE_TGZ ---"
i = s.find(start_tag)
j = s.find(end_tag)
if i < 0 or j < 0 or j <= i:
    raise SystemExit("[ERR] cannot find P570 marker block to replace")
j_end = j + len(end_tag)

new_block = r'''# --- P570_CHECK_INSIDE_CODE_TGZ ---
# --- P576_STREAM_TARLIST_V1 ---
code_tgz="$(ls -1 "$latest_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$code_tgz" ] || { echo "[FAIL] missing VSP_UI_*.tgz in $latest_dir"; exit 5; }
[ -f "$code_tgz" ] || { echo "[FAIL] VSP_UI tgz not found: $code_tgz"; exit 5; }

# Stream check to avoid command-substitution truncation
has_in_tgz(){
  local want="$1"
  tar -tzf "$code_tgz" \
    | sed 's#^\./##' \
    | tr -d '\r' \
    | grep -qxF "$want"
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
  has_in_tgz "$r" || missing+=("$r")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING_IN_CODE_TGZ:${missing[*]}"
  echo "[DBG] code_tgz=$code_tgz"
  echo "[DBG] show matches for bin/config quickly:"
  tar -tzf "$code_tgz" | egrep '(^|^\./)(bin/|config/|RELEASE_NOTES\.md$)' | head -n 80 || true
  exit 5
fi

log "[OK] contract inside code tgz PASS: $(basename "$code_tgz")"
exit 0
# --- END P576_STREAM_TARLIST_V1 ---
# --- END P570_CHECK_INSIDE_CODE_TGZ ---'''

s2 = s[:i] + new_block + s[j_end:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced P570 block with P576 stream checker")
PY

bash -n "$F"
echo "[OK] bash -n ok"

bash bin/verify_release_and_customer_smoke.sh
