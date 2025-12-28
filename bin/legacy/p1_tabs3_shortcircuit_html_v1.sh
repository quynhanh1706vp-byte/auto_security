#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need wc

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_tabs3_sc_${TS}"
echo "[BACKUP] ${W}.bak_tabs3_sc_${TS}"

python3 - <<'PY'
from pathlib import Path
import time, re

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

marker = "VSP_TABS3_SHORTCIRCUIT_HTML_V1"
if marker in s:
    print("[OK] already patched")
else:
    block = r'''
# --- VSP_TABS3_SHORTCIRCUIT_HTML_V1 ---
try:
    from pathlib import Path as _Path

    class _VSPTabs3ShortCircuit:
        def __init__(self, wsgi_app, ui_root: str):
            self.wsgi_app = wsgi_app
            self.ui_root = _Path(ui_root).resolve()
            self.map = {
                "/data_source": self.ui_root / "templates" / "vsp_data_source_2025.html",
                "/settings": self.ui_root / "templates" / "vsp_settings_2025.html",
                "/rule_overrides": self.ui_root / "templates" / "vsp_rule_overrides_2025.html",
            }

        def __call__(self, environ, start_response):
            path = (environ.get("PATH_INFO") or "").strip()
            method = (environ.get("REQUEST_METHOD") or "GET").upper()

            fp = self.map.get(path)
            if fp and fp.exists():
                try:
                    body = fp.read_bytes()
                except Exception:
                    body = b""

                headers = [
                    ("Content-Type", "text/html; charset=utf-8"),
                    ("Cache-Control", "no-store"),
                    ("Content-Length", str(len(body))),
                ]
                start_response("200 OK", headers)

                # HEAD must return no body but keep Content-Length
                if method == "HEAD":
                    return [b""]
                return [body]

            return self.wsgi_app(environ, start_response)

    if "app" in globals() and hasattr(globals()["app"], "wsgi_app"):
        _ui_root = _Path(__file__).resolve().parent
        globals()["app"].wsgi_app = _VSPTabs3ShortCircuit(globals()["app"].wsgi_app, str(_ui_root))
        print("[VSP_TABS3_SC] short-circuit enabled for /data_source,/settings,/rule_overrides")
except Exception as _e:
    print("[VSP_TABS3_SC] disabled:", _e)
# --- /VSP_TABS3_SHORTCIRCUIT_HTML_V1 ---
'''
    s += "\n" + block
    W.write_text(s, encoding="utf-8")
    print("[OK] appended short-circuit block")

print("[DONE]")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart service =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.1

echo "== verify GET body non-zero =="
for p in data_source settings rule_overrides; do
  echo "--- GET /$p bytes"
  curl -fsS "http://127.0.0.1:8910/$p" | wc -c
done

echo "== verify HEAD Content-Length non-zero =="
for p in data_source settings rule_overrides; do
  echo "--- HEAD /$p"
  curl -fsS -I "http://127.0.0.1:8910/$p" | sed -n '1,12p'
done

echo "== quick api check =="
curl -fsS "http://127.0.0.1:8910/api/ui/settings_v2" | head -c 160; echo
curl -fsS "http://127.0.0.1:8910/api/ui/rule_overrides_v2" | head -c 160; echo
