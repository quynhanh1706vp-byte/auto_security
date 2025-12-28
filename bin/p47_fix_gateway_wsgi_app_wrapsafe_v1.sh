#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
GW="wsgi_vsp_ui_gateway.py"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_fix_gateway_wrapsafe_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sudo; need systemctl; need curl; need head; need sed

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

[ -f "$GW" ] || fail "missing $GW"
cp -f "$GW" "${GW}.bak_wrapsafe_${TS}"
ok "backup: ${GW}.bak_wrapsafe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_WSGI_WRAPSAFE_V1"
if MARK not in s:
    helper = r'''
# --- VSP_WSGI_WRAPSAFE_V1 ---
def _vsp_wrapsafe_application(_app, _wrap):
    """
    _wrap: callable that takes a WSGI callable and returns a WSGI callable
    Works when _app is Flask app (has .wsgi_app) OR already a WSGI function.
    """
    try:
        if hasattr(_app, "wsgi_app"):
            _app.wsgi_app = _wrap(_app.wsgi_app)
            return _app
    except Exception:
        pass
    try:
        # _app is likely already WSGI callable
        return _wrap(_app)
    except Exception:
        return _app
# --- /VSP_WSGI_WRAPSAFE_V1 ---
'''.lstrip("\n")

    # put helper near top (after imports) if possible
    m = re.search(r'(?m)^(import .*|from .* import .*)\s*$', s)
    if m:
        # insert after first import block
        m2 = list(re.finditer(r'(?m)^(import .*|from .* import .*)\s*$', s))
        last = m2[-1]
        s = s[:last.end()] + "\n\n" + helper + "\n" + s[last.end():]
    else:
        s = helper + "\n" + s

# Replace all "application.wsgi_app = X(application.wsgi_app)" with wrap-safe form
pat = re.compile(r'(?m)^\s*application\.wsgi_app\s*=\s*([A-Za-z_][A-Za-z0-9_]*)\(\s*application\.wsgi_app\s*\)\s*$')
s, n = pat.subn(r'application = _vsp_wrapsafe_application(application, \1)', s)

p.write_text(s, encoding="utf-8")
print(f"[OK] wrapsafe patch applied, replaced={n}")
PY

python3 -m py_compile "$GW"
ok "py_compile PASS: $GW"

ok "restart $SVC"
sudo systemctl restart "$SVC" || true

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

pass=0
for i in $(seq 1 30); do
  c_vsp5="$(probe http://127.0.0.1:8910/vsp5)"
  c_runs="$(probe http://127.0.0.1:8910/api/vsp/runs?limit=1&offset=0)"
  c_extras="$(probe http://127.0.0.1:8910/api/vsp/dashboard_extras_v1)"
  if [ "$c_vsp5" = "200" ] && [ "$c_runs" = "200" ] && [ "$c_extras" = "200" ]; then pass=1; break; fi
  sleep 0.4
done

if [ "$pass" -eq 1 ]; then
  ok "UP: /vsp5=200, /api/vsp/runs=200, /api/vsp/dashboard_extras_v1=200"
  exit 0
fi

echo "== status ==" | tee -a "$LOG"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
echo "== journal tail ==" | tee -a "$LOG"
sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
tail -n 120 out_ci/ui_8910.error.log 2>/dev/null | tee -a "$LOG" >/dev/null || true
fail "still not healthy (see $LOG)"
