#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
GW="wsgi_vsp_ui_gateway.py"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_fix_gateway_app_after_request_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need curl; need sudo; need systemctl

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

[ -f "$GW" ] || fail "missing $GW"
cp -f "$GW" "${GW}.bak_appfix_${TS}"
ok "backup: ${GW}.bak_appfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK1="VSP_ORIG_FLASK_APP_SAVED_V1"
MARK2="VSP_REPAIR_APP_BEFORE_AFTER_REQUEST_V1"

# 1) Ensure we save original Flask app BEFORE wrapping `application` into a function
# Find the specific wrap line introduced earlier:
wrap_pat = r'(?m)^\s*application\s*=\s*_vsp_dashboard_extras_wsgi_mw\(application\)\s*$'
m = re.search(wrap_pat, s)
if m and MARK1 not in s:
    insert = (
        "# --- %s ---\n"
        "try:\n"
        "    # Keep reference to real Flask app before any WSGI wrapping\n"
        "    _VSP_ORIG_FLASK_APP = application\n"
        "except Exception:\n"
        "    _VSP_ORIG_FLASK_APP = None\n"
        "# --- /%s ---\n"
    ) % (MARK1, MARK1)
    s = s[:m.start()] + insert + s[m.start():]

# 2) Before the first @app.after_request, repair `app` to point to original Flask app
after_pat = r'(?m)^\s*@app\.after_request\s*$'
m2 = re.search(after_pat, s)
if m2 and MARK2 not in s:
    guard = (
        "# --- %s ---\n"
        "try:\n"
        "    # If app has been overwritten by WSGI middleware (function), restore it.\n"
        "    _cand = globals().get('app')\n"
        "    _orig = globals().get('_VSP_ORIG_FLASK_APP')\n"
        "    if (_cand is None) or (not hasattr(_cand, 'after_request')):\n"
        "        if _orig is not None and hasattr(_orig, 'after_request'):\n"
        "            app = _orig\n"
        "except Exception:\n"
        "    pass\n"
        "# --- /%s ---\n"
    ) % (MARK2, MARK2)
    s = s[:m2.start()] + guard + s[m2.start():]

p.write_text(s, encoding="utf-8")
print("[OK] patched gateway (orig flask app + repair before after_request)")
PY

python3 -m py_compile "$GW"
ok "py_compile PASS: $GW"

ok "restart service..."
sudo systemctl restart "$SVC" || true

# wait up to ~8s
pass=0
for i in $(seq 1 20); do
  c1="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/vsp5 2>/dev/null || true)"
  c2="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/api/vsp/dashboard_extras_v1 2>/dev/null || true)"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then pass=1; break; fi
  sleep 0.4
done

if [ "$pass" -eq 1 ]; then
  ok "UP: /vsp5=200 + dashboard_extras_v1=200"
  exit 0
fi

echo "== status ==" | tee -a "$LOG"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
echo "== journal tail ==" | tee -a "$LOG"
sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null | tee -a "$LOG" >/dev/null || true
fail "still not healthy (see $LOG)"
