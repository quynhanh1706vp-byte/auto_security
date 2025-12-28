#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need awk; need head; need tail; need curl; need systemctl; need sudo

TS="$(date +%Y%m%d_%H%M%S)"
LOG_TXT="$OUT/p47_rescue_gateway_extras_${TS}.txt"

ok(){ echo "[OK] $*" | tee -a "$LOG_TXT"; }
warn(){ echo "[WARN] $*" | tee -a "$LOG_TXT" >&2; }
fail(){ echo "[FAIL] $*" | tee -a "$LOG_TXT" >&2; exit 2; }

echo "== [P47-RESCUE] gateway extras + restart ==" | tee "$LOG_TXT"
echo "[INFO] SVC=$SVC BASE=$BASE" | tee -a "$LOG_TXT"

# 0) Locate which module is served (from ExecStart)
EX="$(systemctl show "$SVC" -p ExecStart --no-pager | sed 's/^ExecStart=//')"
echo "[INFO] ExecStart=$EX" | tee -a "$LOG_TXT"

# Expect something like "wsgi_vsp_ui_gateway:application"
MOD="$(echo "$EX" | awk '{for(i=1;i<=NF;i++){if($i ~ /:[A-Za-z_][A-Za-z0-9_]*$/){print $i; exit}}}')"
[ -n "${MOD:-}" ] || fail "cannot parse module:callable from ExecStart"
MOD_FILE="${MOD%%:*}.py"
CALLABLE="${MOD##*:}"

[ -f "$MOD_FILE" ] || fail "missing gateway file: $MOD_FILE (from ExecStart module $MOD)"
ok "gateway module=$MOD_FILE callable=$CALLABLE"

# 1) Backup gateway file
cp -f "$MOD_FILE" "${MOD_FILE}.bak_extras_${TS}"
ok "backup: ${MOD_FILE}.bak_extras_${TS}"

# 2) Patch gateway: register /api/vsp/dashboard_extras_v1 on the actual WSGI app object
python3 - <<PY
from pathlib import Path
import re

p=Path("$MOD_FILE")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_API_DASHBOARD_EXTRAS_V1_GATEWAY"
if MARK in s:
    print("[OK] gateway already has dashboard_extras patch")
    raise SystemExit(0)

snippet = r'''
# --- VSP_API_DASHBOARD_EXTRAS_V1_GATEWAY (commercial: fast + stable) ---
def _vsp__dashboard_extras_payload(rid=""):
    import os, socket, datetime
    return {
        "ok": True,
        "ts": datetime.datetime.utcnow().isoformat() + "Z",
        "rid": rid or "",
        "extras": {"notes": [], "degraded": False},
        "build": {"host": socket.gethostname(), "pid": os.getpid()},
    }

def _vsp__register_dashboard_extras_v1(_app):
    # Register without decorators to avoid NameError issues
    try:
        from flask import jsonify, request
    except Exception:
        jsonify = None
        request = None

    def handler():
        try:
            rid=""
            try:
                rid = (request.args.get("rid","") if request else "") or ""
            except Exception:
                rid = ""
            payload = _vsp__dashboard_extras_payload(rid)
            if jsonify:
                return jsonify(payload)
            import json
            return (json.dumps(payload), 200, {"Content-Type":"application/json"})
        except Exception as e:
            # Never crash worker
            try:
                if jsonify:
                    return jsonify({"ok": False, "error": str(e)}), 200
            except Exception:
                pass
            import json
            return (json.dumps({"ok": False, "error": str(e)}), 200, {"Content-Type":"application/json"})

    try:
        _app.add_url_rule("/api/vsp/dashboard_extras_v1",
                          "vsp_dashboard_extras_v1",
                          handler,
                          methods=["GET"])
    except Exception:
        # if already registered or app isn't flask-like, ignore
        pass

# Auto-detect the running app object in this module
try:
    __vsp_app = globals().get("application") or globals().get("app")
    if __vsp_app is not None and hasattr(__vsp_app, "add_url_rule"):
        _vsp__register_dashboard_extras_v1(__vsp_app)
except Exception:
    pass
# --- /VSP_API_DASHBOARD_EXTRAS_V1_GATEWAY ---
'''.lstrip("\n")

# Insert near end but before __main__ if any
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s2 = s[:m.start()] + "\n\n" + snippet + "\n\n" + s[m.start():]
else:
    s2 = s.rstrip() + "\n\n" + snippet + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched gateway dashboard_extras_v1")
PY

# 3) Safety compile (syntax)
python3 -m py_compile "$MOD_FILE" || fail "py_compile failed for $MOD_FILE"
ok "py_compile PASS: $MOD_FILE"

# 4) IMPORTANT: Your previous patch in vsp_demo_app.py might have caused crash if imported somewhere.
# If it has the marker VSP_DASHBOARD_EXTRAS_V1, convert it to a safe add_url_rule registration (no @app.route).
if [ -f "vsp_demo_app.py" ]; then
  if grep -q "VSP_DASHBOARD_EXTRAS_V1" vsp_demo_app.py 2>/dev/null; then
    cp -f vsp_demo_app.py "vsp_demo_app.py.bak_extras_rescue_${TS}"
    ok "backup: vsp_demo_app.py.bak_extras_rescue_${TS}"
    python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace any decorator-based block we added with a safe block
# (keep marker so it won't repatch repeatedly)
pat = r'(?s)# --- VSP_DASHBOARD_EXTRAS_V1.*?# --- /VSP_DASHBOARD_EXTRAS_V1 ---'
if not re.search(pat, s):
    print("[OK] marker not found in vsp_demo_app.py (skip)")
    raise SystemExit(0)

safe = r'''
# --- VSP_DASHBOARD_EXTRAS_V1 (commercial: safe registration) ---
def _vsp__demo_register_dashboard_extras(_app):
    try:
        from flask import jsonify, request
    except Exception:
        jsonify = None
        request = None
    def handler():
        rid=""
        try:
            rid = request.args.get("rid","") if request else ""
        except Exception:
            rid=""
        payload={"ok": True, "rid": rid or "", "extras": {"notes": [], "degraded": False}}
        if jsonify:
            return jsonify(payload)
        import json
        return (json.dumps(payload), 200, {"Content-Type":"application/json"})
    try:
        _app.add_url_rule("/api/vsp/dashboard_extras_v1",
                          "vsp_dashboard_extras_v1_demo",
                          handler,
                          methods=["GET"])
    except Exception:
        pass

try:
    __vsp_app = globals().get("app") or globals().get("application")
    if __vsp_app is not None and hasattr(__vsp_app, "add_url_rule"):
        _vsp__demo_register_dashboard_extras(__vsp_app)
except Exception:
    pass
# --- /VSP_DASHBOARD_EXTRAS_V1 ---
'''.lstrip("\n")

s2 = re.sub(pat, safe, s)
p.write_text(s2, encoding="utf-8")
print("[OK] rewrote vsp_demo_app.py extras block to safe registration")
PY
    python3 -m py_compile vsp_demo_app.py || fail "py_compile failed for vsp_demo_app.py"
    ok "py_compile PASS: vsp_demo_app.py"
  else
    ok "vsp_demo_app.py exists but no marker -> not touching"
  fi
else
  ok "vsp_demo_app.py not found -> skip"
fi

# 5) Restart service and verify endpoints
ok "restart service..."
sudo systemctl restart "$SVC" || true

# Check it is actually running (not active-exited)
state="$(systemctl show "$SVC" -p ActiveState -p SubState --no-pager | tr '\n' ' ')"
ok "state: $state"

# Wait for /vsp5 and dashboard_extras_v1
ok "probe /vsp5 and /api/vsp/dashboard_extras_v1 ..."
code1="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 3 "http://127.0.0.1:8910/vsp5" 2>/dev/null || true)"
code2="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 3 "http://127.0.0.1:8910/api/vsp/dashboard_extras_v1" 2>/dev/null || true)"
echo "[INFO] vsp5=$code1 extras=$code2" | tee -a "$LOG_TXT"

if [ "$code1" != "200" ] || [ "$code2" != "200" ]; then
  warn "not healthy yet -> show status + journal tail"
  systemctl status "$SVC" --no-pager | tee -a "$LOG_TXT" >/dev/null || true
  sudo journalctl -u "$SVC" --no-pager -n 120 | tee -a "$LOG_TXT" >/dev/null || true
  fail "service not healthy on required endpoints (see $LOG_TXT)"
fi

ok "UP: /vsp5=200 and dashboard_extras_v1=200"
ok "DONE"
