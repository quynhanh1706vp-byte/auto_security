#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
GW="wsgi_vsp_ui_gateway.py"
OUT="out_ci"; mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_rescue_gateway_wrapsafe_v2_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$LOG"; exit 2; }; }
need date; need ls; need head; need python3; need sudo; need systemctl; need curl; need grep; need awk

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

[ -f "$GW" ] || fail "missing $GW"

ok "== [P47 RESCUE WRAPSAFE v2] ts=$TS =="
cp -f "$GW" "${GW}.bak_before_wrapsafe_v2_${TS}"
ok "backup current: ${GW}.bak_before_wrapsafe_v2_${TS}"

# 1) restore newest backup that py_compile PASS
picked=""
for f in $(ls -1t ${GW}.bak_* 2>/dev/null | head -n 200); do
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    picked="$f"; break
  fi
done
[ -n "$picked" ] || fail "no compile-pass backup found: ${GW}.bak_*"
cp -f "$picked" "$GW"
ok "restored from: $picked"
python3 -m py_compile "$GW"
ok "py_compile PASS after restore"

# 2) apply wrapsafe patch, INDENT-AWARE (never breaks try blocks)
python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_WSGI_WRAPSAFE_V2"

helper = r'''
# --- VSP_WSGI_WRAPSAFE_V2 ---
def _vsp_wrapsafe_application(_app, _wrap):
    """
    _wrap: callable(WsgiCallable)->WsgiCallable
    Works if _app is Flask app (has .wsgi_app) OR already a WSGI callable.
    """
    try:
        if hasattr(_app, "wsgi_app"):
            _app.wsgi_app = _wrap(_app.wsgi_app)
            return _app
    except Exception:
        pass
    try:
        return _wrap(_app)
    except Exception:
        return _app
# --- /VSP_WSGI_WRAPSAFE_V2 ---
'''.lstrip("\n")

if MARK not in s:
    # Insert helper safely at top-level (after shebang if any)
    if s.startswith("#!"):
        nl = s.find("\n")
        s = s[:nl+1] + "\n" + helper + "\n" + s[nl+1:]
    else:
        s = helper + "\n" + s

# Replace lines: application.wsgi_app = X(application.wsgi_app)
# Preserve indentation so try/if blocks remain valid.
pat = re.compile(
    r'(?m)^(?P<ind>[ \t]*)application\.wsgi_app\s*=\s*(?P<w>[A-Za-z_][A-Za-z0-9_]*)\(\s*application\.wsgi_app\s*\)\s*$'
)
def repl(m):
    ind=m.group("ind")
    w=m.group("w")
    return f"{ind}application = _vsp_wrapsafe_application(application, {w})"
s, n = pat.subn(repl, s)

p.write_text(s, encoding="utf-8")
print("[OK] wrapsafe v2 applied; replaced=", n)
PY

python3 -m py_compile "$GW"
ok "py_compile PASS after wrapsafe v2"

# 3) restart + probes
ok "restart $SVC"
sudo systemctl restart "$SVC" || true

probe(){ curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$1" 2>/dev/null || true; }

pass=0
for i in $(seq 1 30); do
  c1="$(probe http://127.0.0.1:8910/vsp5)"
  c2="$(probe http://127.0.0.1:8910/api/vsp/runs?limit=1&offset=0)"
  c3="$(probe http://127.0.0.1:8910/api/vsp/dashboard_extras_v1)"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ] && [ "$c3" = "200" ]; then pass=1; break; fi
  sleep 0.4
done

if [ "$pass" -eq 1 ]; then
  ok "UP: /vsp5=200, /api/vsp/runs=200, /api/vsp/dashboard_extras_v1=200"
  exit 0
fi

warn "not healthy; dump status+journal+error tail"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
sudo journalctl -u "$SVC" --no-pager -n 140 | tee -a "$LOG" >/dev/null || true
tail -n 140 out_ci/ui_8910.error.log 2>/dev/null | tee -a "$LOG" >/dev/null || true
fail "still not healthy (see $LOG)"
