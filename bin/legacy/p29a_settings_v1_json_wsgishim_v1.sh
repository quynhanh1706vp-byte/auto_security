#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
CFG="/home/test/Data/SECURITY_BUNDLE/ui/config/settings_v1.json"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p29a_settingsjson_${TS}"
echo "[BACKUP] ${F}.bak_p29a_settingsjson_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P29A_SETTINGS_V1_JSON_WSGISHIM_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    sys.exit(0)

block = r'''
# ===================== VSP_P29A_SETTINGS_V1_JSON_WSGISHIM_V1 =====================
# Commercial-safe: ensure /api/vsp/settings_v1 returns JSON (audit expects JSON).
try:
    import json
    from pathlib import Path as _Path

    def _vsp_p29a__shim_settings_v1(_wsgi_app):
        if not callable(_wsgi_app):
            return _wsgi_app

        def _app(environ, start_response):
            try:
                if (environ.get("PATH_INFO") or "") == "/api/vsp/settings_v1":
                    cfg = _Path("/home/test/Data/SECURITY_BUNDLE/ui/config/settings_v1.json")
                    if cfg.is_file():
                        body = cfg.read_text(encoding="utf-8", errors="replace")
                        # Validate JSON; if invalid, wrap as string payload.
                        try:
                            json.loads(body)
                            payload = body
                        except Exception:
                            payload = json.dumps({"ok": False, "error": "settings_v1.json invalid-json", "raw": body[:4000]})
                    else:
                        payload = json.dumps({"ok": False, "error": "settings_v1.json missing", "path": str(cfg)})

                    headers = [
                        ("Content-Type", "application/json"),
                        ("Cache-Control", "no-store"),
                    ]
                    start_response("200 OK", headers)
                    return [payload.encode("utf-8", errors="ignore")]
            except Exception:
                # never break original app
                pass
            return _wsgi_app(environ, start_response)

        return _app

    if "application" in globals() and callable(globals().get("application")):
        globals()["application"] = _vsp_p29a__shim_settings_v1(globals()["application"])
    if "app" in globals() and callable(globals().get("app")):
        globals()["app"] = _vsp_p29a__shim_settings_v1(globals()["app"])

    print("[VSP_P29A] settings_v1 JSON shim installed")
except Exception as _e:
    print("[VSP_P29A] ERROR:", _e)
# ===================== /VSP_P29A_SETTINGS_V1_JSON_WSGISHIM_V1 =====================
'''
p.write_text(s.rstrip()+"\n\n"+block+"\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

python3 -m py_compile "$F"

if command -v systemctl >/dev/null 2>&1; then
  echo "== [RESTART] $SVC =="
  sudo systemctl restart "$SVC"
  sudo systemctl --no-pager --full status "$SVC" | head -n 15 || true
fi

echo "== [SMOKE] settings_v1 content-type =="
BASE="${BASE:-${VSP_UI_BASE:-http://127.0.0.1:8910}}"
curl -fsS -o /dev/null -D- "$BASE/api/vsp/settings_v1" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:/ {print}'
