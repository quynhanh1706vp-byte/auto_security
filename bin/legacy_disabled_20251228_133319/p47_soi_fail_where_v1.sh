#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_soi_fail_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need sudo; need date; need tail; need grep; need awk; need sed
command -v ss >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true

echo "== [P47 SOI FAIL] ==" | tee "$LOG"
echo "[INFO] svc=$SVC ts=$TS" | tee -a "$LOG"

echo "== systemctl show 핵 ==" | tee -a "$LOG"
systemctl show "$SVC" -p ActiveState -p SubState -p NRestarts -p ExecMainCode -p ExecMainStatus -p MainPID -p ExecStart -p DropInPaths --no-pager \
  | tee -a "$LOG"

echo -e "\n== systemctl status ==" | tee -a "$LOG"
systemctl status "$SVC" --no-pager | tee -a "$LOG" || true

if command -v ss >/dev/null 2>&1; then
  echo -e "\n== ss :8910 ==" | tee -a "$LOG"
  ss -lntp 2>/dev/null | egrep '(:8910|gunicorn|python)' | tee -a "$LOG" || true
fi

echo -e "\n== journal tail 200 ==" | tee -a "$LOG"
sudo journalctl -u "$SVC" --no-pager -n 200 | tee -a "$LOG" || true

ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
if [ -f "$ERRLOG" ]; then
  echo -e "\n== error log tail 200 ==" | tee -a "$LOG"
  tail -n 200 "$ERRLOG" | tee -a "$LOG" || true
else
  echo -e "\n[WARN] missing $ERRLOG" | tee -a "$LOG"
fi

# Import test with same venv python (if exists)
VENV_PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
if [ -x "$VENV_PY" ]; then
  echo -e "\n== import test wsgi_vsp_ui_gateway ==" | tee -a "$LOG"
  set +e
  "$VENV_PY" - <<'PY' >>"$LOG" 2>&1
import importlib, traceback
try:
    m=importlib.import_module("wsgi_vsp_ui_gateway")
    app=getattr(m,"application",None)
    print("IMPORT_OK", "application_type=", type(app).__name__, "has_add_url_rule=", hasattr(app,"add_url_rule"))
except Exception as e:
    print("IMPORT_FAIL", repr(e))
    traceback.print_exc()
PY
  set -e
fi

echo "[OK] wrote $LOG"
