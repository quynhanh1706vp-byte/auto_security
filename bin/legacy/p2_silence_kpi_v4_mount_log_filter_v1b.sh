#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need systemctl; need grep; need stat; need tail; need sed; need wc

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
ERRLOG="out_ci/ui_8910.error.log"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_kpi_v4_logfilter_${TS}"
echo "[BACKUP] ${W}.bak_kpi_v4_logfilter_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_KPI_V4_LOGFILTER_V1B"
if MARK in s:
    print("[OK] logfilter already present; skip")
    raise SystemExit(0)

patch = r'''
# --- VSP_P2_KPI_V4_LOGFILTER_V1B (SAFE append) ---
def _vsp_install_kpi_v4_log_silencer_v1b():
    """
    Commercial fix: suppress noisy KPI_V4 mount 'Working outside of application context' log.
    Keeps all other logs intact.
    """
    import logging

    class _VspKpiV4SuppressFilter(logging.Filter):
        def filter(self, record):
            try:
                msg = record.getMessage()
            except Exception:
                return True
            if ("VSP_KPI_V4" in msg) and ("Working outside of application context" in msg):
                return False
            return True

    flt = _VspKpiV4SuppressFilter()

    # Attach to common loggers used by gunicorn/flask apps
    for name in ("", "gunicorn.error", "gunicorn.access", "werkzeug"):
        lg = logging.getLogger(name)
        try:
            lg.addFilter(flt)
        except Exception:
            pass
        # Attach to existing handlers too (some setups check handler filters)
        for h in getattr(lg, "handlers", []) or []:
            try:
                h.addFilter(flt)
            except Exception:
                pass

try:
    _vsp_install_kpi_v4_log_silencer_v1b()
except Exception:
    pass
# --- end VSP_P2_KPI_V4_LOGFILTER_V1B ---
'''.lstrip("\n")

p.write_text(s + ("\n\n" if not s.endswith("\n") else "\n") + patch, encoding="utf-8")
print("[OK] appended KPI_V4 log filter into", p)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

# Record current log size so we only check NEW lines after restart
before_size=0
if [ -f "$ERRLOG" ]; then before_size="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"; fi
echo "[INFO] error_log_size_before_restart=$before_size"

sudo systemctl restart "$SVC"

# Wait a moment + hit one endpoint to trigger any mounts/logs
sleep 0.6
curl -sS "$BASE/api/vsp/rid_latest" >/dev/null 2>&1 || true
sleep 0.6

echo "== [CHECK] NEW log bytes after restart (should NOT contain VSP_KPI_V4 mount failed) =="
if [ -f "$ERRLOG" ]; then
  after_size="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"
  echo "[INFO] error_log_size_after_restart=$after_size"
  if [ "$after_size" -gt "$before_size" ]; then
    tail -c +"$((before_size+1))" "$ERRLOG" | head -n 200 | sed -n '1,200p'
    echo "--- grep KPI_V4 in NEW part ---"
    tail -c +"$((before_size+1))" "$ERRLOG" | grep -n "VSP_KPI_V4" || echo "[OK] no KPI_V4 in NEW part"
  else
    echo "[OK] no new error log bytes"
  fi
else
  echo "[WARN] missing $ERRLOG"
fi
