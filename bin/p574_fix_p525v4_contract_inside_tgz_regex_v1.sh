#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/legacy/p525_verify_release_and_customer_smoke_v4.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p574_${TS}"
echo "[OK] backup => ${F}.bak_p574_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("bin/legacy/p525_verify_release_and_customer_smoke_v4.sh")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "P574_CONTRACT_REGEX_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find the contract section start. We'll replace everything from "== [3] contract check" up to the first "exit 0" that belongs to the injected block.
start = re.search(r'(?m)^\s*log\s+"\=\=\s*\[3\]\s*contract check \(NEW commercial\)\s*\=\="\s*$', s)
if not start:
    print("[ERR] cannot find contract log line")
    raise SystemExit(2)

# Find where the injected contract block ends (we look for the line that logs PASS and then exit 0, or just "exit 0" after the contract section).
# We'll replace from the log line to the next line that contains "exit 0" (first occurrence after start).
tail = re.search(r'(?ms)\G.*?^\s*exit\s+0\s*$', s[start.end():])
# The \G trick may not work; fallback: find first exit 0 after start
m_exit = re.search(r'(?m)^\s*exit\s+0\s*$', s[start.end():])
if not m_exit:
    print("[ERR] cannot find 'exit 0' after contract section")
    raise SystemExit(2)

end_pos = start.end() + m_exit.end()

replacement = r'''
log "== [3] contract check (NEW commercial) =="

# --- ''' + marker + r''' ---
code_tgz="$(ls -1 "$latest_dir"/VSP_UI_*.tgz 2>/dev/null | head -n1 || true)"
[ -n "$code_tgz" ] || { echo "[FAIL] missing VSP_UI_*.tgz in $latest_dir"; exit 5; }

tar_list="$(tar -tzf "$code_tgz")"

# helper: match both "path" and "./path"
has(){
  local pat="$1"
  echo "$tar_list" | grep -Eq "$pat"
}

missing=()

# config templates + notes
has '^(\./)?config/systemd_unit\.template$'        || missing+=("config/systemd_unit.template")
has '^(\./)?config/logrotate_vsp-ui\.template$'    || missing+=("config/logrotate_vsp-ui.template")
has '^(\./)?config/production\.env\.example$'      || missing+=("config/production.env.example")
has '^(\./)?RELEASE_NOTES\.md$'                    || missing+=("RELEASE_NOTES.md")

# 4 entrypoints
has '^(\./)?bin/ui_gate\.sh$'                      || missing+=("bin/ui_gate.sh")
has '^(\./)?bin/verify_release_and_customer_smoke\.sh$' || missing+=("bin/verify_release_and_customer_smoke.sh")
has '^(\./)?bin/pack_release\.sh$'                 || missing+=("bin/pack_release.sh")
has '^(\./)?bin/ops\.sh$'                          || missing+=("bin/ops.sh")

if [ "${#missing[@]}" -gt 0 ]; then
  echo "MISSING_IN_CODE_TGZ:${missing[*]}"
  exit 5
fi

log "[OK] contract inside code tgz PASS: $(basename "$code_tgz")"
exit 0
# --- END ''' + marker + r''' ---
'''.lstrip("\n")

s2 = s[:start.start()] + replacement + s[end_pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched contract inside tgz regex matcher")
PY

bash -n "$F"
echo "[OK] bash -n ok"

bash bin/verify_release_and_customer_smoke.sh
