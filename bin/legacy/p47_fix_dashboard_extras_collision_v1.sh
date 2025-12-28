#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

GW="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

OUT="out_ci"
mkdir -p "$OUT"
TS="$(date +%Y%m%d_%H%M%S)"
LOG="$OUT/p47_fix_extras_collision_${TS}.txt"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need awk; need head; need tail; need curl; need sudo; need systemctl

ok(){ echo "[OK] $*" | tee -a "$LOG"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG" >&2; exit 2; }

echo "== [P47 FIX] dashboard_extras collision ==" | tee "$LOG"
echo "[INFO] SVC=$SVC BASE=$BASE" | tee -a "$LOG"

[ -f "$GW" ] || fail "missing $GW"
[ -f "$APP" ] || warn "missing $APP (will skip app patch)"

cp -f "$GW" "${GW}.bak_extras_mw_${TS}"
ok "backup: ${GW}.bak_extras_mw_${TS}"
if [ -f "$APP" ]; then
  cp -f "$APP" "${APP}.bak_extras_disable_${TS}"
  ok "backup: ${APP}.bak_extras_disable_${TS}"
fi

# 1) Patch gateway: add WSGI middleware wrapper AFTER application is created
python3 - <<'PY'
from pathlib import Path
import re

gw = Path("wsgi_vsp_ui_gateway.py")
s = gw.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_WSGI_MW_DASHBOARD_EXTRAS_V1"
if MARK in s:
    print("[OK] gateway already has WSGI extras middleware")
    raise SystemExit(0)

# Find the line where application is assigned from demo app import
m = re.search(r'(?m)^\s*application\s*=\s*_p3f_import_vsp_demo_app\(\)\s*$', s)
if not m:
    # fallback: first plain "application =" assignment (safer than nothing)
    m = re.search(r'(?m)^\s*application\s*=\s*.+$', s)
if not m:
    raise SystemExit("[ERR] cannot find application assignment in gateway")

snippet = r'''
# --- VSP_WSGI_MW_DASHBOARD_EXTRAS_V1 (commercial: always-fast, no Flask routing) ---
def _vsp_dashboard_extras_wsgi_mw(_app):
    import json, datetime, os, socket
    def _mw(environ, start_response):
        try:
            if environ.get("PATH_INFO","") == "/api/vsp/dashboard_extras_v1":
                rid = ""
                try:
                    qs = environ.get("QUERY_STRING","") or ""
                    # tiny parse (avoid urllib heavy)
                    for part in qs.split("&"):
                        if part.startswith("rid="):
                            rid = part[4:]
                            break
                except Exception:
                    rid = ""
                payload = {
                    "ok": True,
                    "ts": datetime.datetime.utcnow().isoformat() + "Z",
                    "rid": rid or "",
                    "extras": {"notes": [], "degraded": False},
                    "build": {"host": socket.gethostname(), "pid": os.getpid()},
                }
                body = json.dumps(payload, separators=(",",":")).encode("utf-8")
                headers = [
                    ("Content-Type","application/json"),
                    ("Cache-Control","no-store"),
                    ("Content-Length", str(len(body))),
                ]
                start_response("200 OK", headers)
                return [body]
        except Exception:
            pass
        return _app(environ, start_response)
    return _mw

try:
    if callable(globals().get("application")):
        application = _vsp_dashboard_extras_wsgi_mw(application)
        print("[VSP_WSGI_MW_DASHBOARD_EXTRAS_V1] installed")
except Exception:
    pass
# --- /VSP_WSGI_MW_DASHBOARD_EXTRAS_V1 ---
'''.lstrip("\n")

# Insert immediately AFTER the matched application assignment block
insert_at = m.end()
s2 = s[:insert_at] + "\n\n" + snippet + "\n" + s[insert_at:]

gw.write_text(s2, encoding="utf-8")
print("[OK] patched gateway WSGI extras middleware")
PY

python3 -m py_compile "$GW"
ok "py_compile PASS: $GW"

# 2) Patch vsp_demo_app.py: disable any dashboard_extras_v1 route blocks (prevents overwrite endpoint)
if [ -f "$APP" ]; then
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# (a) If our marker block exists, replace it with a disabled stub
if "VSP_DASHBOARD_EXTRAS_V1" in s:
    s = re.sub(
        r'(?s)# --- VSP_DASHBOARD_EXTRAS_V1.*?# --- /VSP_DASHBOARD_EXTRAS_V1 ---',
        '# --- VSP_DASHBOARD_EXTRAS_V1 (disabled; served by gateway WSGI MW) ---\n'
        '# NOTE: disabled to avoid Flask endpoint overwrite crash.\n'
        '# --- /VSP_DASHBOARD_EXTRAS_V1 ---',
        s
    )

# (b) Also comment-out any stray decorator lines for this path
lines = s.splitlines(True)
out=[]
skip = 0
for i,line in enumerate(lines):
    if '@app.route("/api/vsp/dashboard_extras_v1"' in line or "@app.route('/api/vsp/dashboard_extras_v1'" in line:
        out.append("# [DISABLED_BY_P47_FIX] " + line)
        skip = 120  # comment some following lines to be safe
        continue
    if skip>0:
        out.append("# [DISABLED_BY_P47_FIX] " + line)
        skip -= 1
        # stop early if we hit an obvious end marker
        if "VSP_DASHBOARD_EXTRAS_V1" in line and "/VSP_DASHBOARD_EXTRAS_V1" in line:
            skip = 0
        continue
    out.append(line)

p.write_text("".join(out), encoding="utf-8")
print("[OK] disabled dashboard_extras_v1 routes in vsp_demo_app.py")
PY

python3 -m py_compile "$APP"
ok "py_compile PASS: $APP"
fi

# 3) Restart + probes
ok "restart service..."
sudo systemctl restart "$SVC" || true

# wait port
for i in $(seq 1 20); do
  c1="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/vsp5 2>/dev/null || true)"
  c2="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/api/vsp/dashboard_extras_v1 2>/dev/null || true)"
  if [ "$c1" = "200" ] && [ "$c2" = "200" ]; then
    ok "UP: /vsp5=200 + dashboard_extras_v1=200"
    curl -sS --connect-timeout 1 --max-time 2 http://127.0.0.1:8910/api/vsp/dashboard_extras_v1 | head -c 240; echo
    ok "log: $LOG"
    exit 0
  fi
  sleep 0.4
done

warn "not healthy; show last journal + error log tail"
systemctl status "$SVC" --no-pager | tee -a "$LOG" >/dev/null || true
sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG" >/dev/null || true
tail -n 120 "$OUT/ui_8910.error.log" 2>/dev/null | tee -a "$LOG" >/dev/null || true
fail "still not healthy (see $LOG)"
