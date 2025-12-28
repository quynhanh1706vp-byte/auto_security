#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="bin/commercial_ui_audit_v2.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_waitup_slow_${TS}"
echo "[BACKUP] ${F}.bak_waitup_slow_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("bin/commercial_ui_audit_v2.sh")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_AUDIT_WAITUP_SLOW_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

block = r'''
# ===================== VSP_AUDIT_WAITUP_SLOW_V1 =====================
# Override base selection + wait_up to tolerate slow /vsp5 (>2s) and prefer fast selfcheck endpoint.

_choose_base(){
  local cand=("$BASE" "http://127.0.0.1:8910" "http://localhost:8910" "http://[::1]:8910")
  for b in "${cand[@]}"; do
    [ -n "$b" ] || continue
    # Prefer fast readiness probe first
    if curl -fsS --connect-timeout 2 --max-time 5 -o /dev/null "$b/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
    # Fallback to /vsp5 with bigger budget
    if curl -fsS --connect-timeout 2 --max-time 12 -o /dev/null "$b/vsp5" >/dev/null 2>&1; then
      BASE="$b"; return 0
    fi
  done
  return 1
}

wait_up(){
  _choose_base || { red "UI not reachable (all base candidates failed)"; return 1; }
  for i in $(seq 1 40); do
    if curl_do 6 -o /dev/null "$BASE/api/vsp/selfcheck_p0" >/dev/null 2>&1; then
      pass "UI up (selfcheck): $BASE"
      return 0
    fi
    if curl_do 12 -o /dev/null "$BASE/vsp5" >/dev/null 2>&1; then
      pass "UI up (/vsp5): $BASE"
      return 0
    fi
    sleep 0.25
  done
  red "UI not reachable: $BASE"
  return 1
}
# ===================== /VSP_AUDIT_WAITUP_SLOW_V1 =====================
'''
p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

echo "[OK] patched $F"
