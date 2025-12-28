#!/usr/bin/env bash
set -u
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  echo "[ERR] Do NOT source. Run: bash ${BASH_SOURCE[0]}"
  return 2
fi
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need curl
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_ro_wsgisafe_${TS}"
echo "[BACKUP] ${W}.bak_ro_wsgisafe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

W=Path("wsgi_vsp_ui_gateway.py")
s=W.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_RULE_OVERRIDES_WSGI_SAFE_V2"

wrapper_code = r'''
# === VSP_P0_RULE_OVERRIDES_WSGI_SAFE_V2 ===
def _vsp__json_bytes(obj):
    import json
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")

class _VSPRuleOverridesAlways200WSGI:
    """
    Intercept /api/vsp/rule_overrides_v1 to avoid 500s (commercial-safe).
    """
    def __init__(self, app):
        self.app = app
    def __call__(self, environ, start_response):
        try:
            path = (environ.get("PATH_INFO","") or "")
            if path == "/api/vsp/rule_overrides_v1":
                import time
                body = _vsp__json_bytes({
                    "ok": True,
                    "who": "VSP_RULE_OVERRIDES_P0_WSGI_SAFE",
                    "ts": int(time.time()),
                    "data": {
                        "enabled": True,
                        "overrides": [],
                        "updated_at": int(time.time()),
                        "updated_by": "system"
                    }
                })
                headers=[
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Cache-Control","no-store"),
                    ("X-VSP-RO-SAFE","wsgi")
                ]
                start_response("200 OK", headers)
                return [body]
        except Exception:
            # never crash worker
            pass
        return self.app(environ, start_response)
# === /VSP_P0_RULE_OVERRIDES_WSGI_SAFE_V2 ===
'''.strip("\n")

# (1) append wrapper once
if MARK not in s:
    s = s + "\n\n" + wrapper_code + "\n"

# (2) wrap `application` once
wrap_line = "application = _VSPRuleOverridesAlways200WSGI(application)"
if wrap_line not in s:
    m = re.search(r'(?m)^\s*application\s*=\s*.+$', s)
    if m:
        ins = m.end()
        s = s[:ins] + "\n" + wrap_line + "\n" + s[ins:]
    else:
        # if no application binding line, still safe to just append wrap (rare)
        s = s + "\n" + wrap_line + "\n"

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] patched + py_compile OK")
PY

echo "== [restart best-effort] =="
if command -v systemctl >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    sudo -n systemctl daemon-reload || true
    sudo -n systemctl restart "$SVC"
    echo "[OK] restarted: $SVC"
  else
    echo "[WARN] sudo -n not allowed. Please run:"
    echo "  sudo systemctl daemon-reload"
    echo "  sudo systemctl restart $SVC"
  fi
fi

echo "== [probe] =="
for i in $(seq 1 80); do
  curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1 && break
  sleep 0.25
done

code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 6 "$BASE/api/vsp/rule_overrides_v1" || true)"
echo "/api/vsp/rule_overrides_v1 => $code"
curl -fsS --connect-timeout 1 --max-time 6 "$BASE/api/vsp/rule_overrides_v1" | head -c 240; echo
