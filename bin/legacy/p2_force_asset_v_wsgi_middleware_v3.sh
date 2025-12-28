#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed; need sort

PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd ($SVC)"; exit 2
fi
echo "[OK] pinned VSP_ASSET_V=$PIN"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_wsgi_mw_v3_${TS}"
echo "[BACKUP] ${W}.bak_wsgi_mw_v3_${TS}"

python3 - "$W" "$PIN" <<'PY'
import sys
from pathlib import Path

fn=sys.argv[1]; pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_WSGI_MIDDLEWARE_PIN_ASSET_V_V3"
if marker in s:
    print("[OK] marker already present; skip append")
    sys.exit(0)

block = r'''
# --- VSP_P2_WSGI_MIDDLEWARE_PIN_ASSET_V_V3 ---
# Commercial+ strict: wrap final WSGI callable so EVERY HTML response is rewritten.
try:
    import os as _os
    import re as _re

    _VSP_PIN_ASSET_V = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS") or "__PIN__"
    _CORE = (
        "vsp_bundle_tabs5_v1.js",
        "vsp_dashboard_luxe_v1.js",
        "vsp_tabs4_autorid_v1.js",
        "vsp_topbar_commercial_v1.js",
    )
    _re_core = _re.compile(
        r'(/static/(?:js|css)/)(' + '|'.join([_re.escape(x) for x in _CORE]) + r')(?:\?[^"\'\s>]*)?'
    )

    class _VspAssetPinMiddleware:
        def __init__(self, app):
            self.app = app

        def __call__(self, environ, start_response):
            captured = {"status": None, "headers": None, "exc": None}

            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers or [])
                captured["exc"] = exc_info
                # don't call real start_response yet
                return None

            it = self.app(environ, _sr)

            status = captured["status"] or "200 OK"
            headers = captured["headers"] or []
            exc = captured["exc"]

            # helper header ops
            def _get(name):
                n=name.lower()
                for k,v in headers:
                    if (k or "").lower()==n:
                        return v
                return ""

            def _set(name, val):
                n=name.lower()
                out=[]
                replaced=False
                for k,v in headers:
                    if (k or "").lower()==n:
                        if not replaced:
                            out.append((name, val))
                            replaced=True
                    else:
                        out.append((k,v))
                if not replaced:
                    out.append((name, val))
                return out

            def _drop(name):
                n=name.lower()
                return [(k,v) for (k,v) in headers if (k or "").lower()!=n]

            ctype = (_get("Content-Type") or "").lower()
            # always expose debug header so we KNOW middleware is active
            headers = _set("X-VSP-ASSET-REWRITE", "mw")
            headers = _set("X-VSP-ASSET-V", str(_VSP_PIN_ASSET_V))

            if "text/html" not in ctype:
                start_response(status, headers, exc)
                return it

            # materialize body (HTML pages are small)
            try:
                body = b"".join(it)
                try:
                    close = getattr(it, "close", None)
                    if callable(close):
                        close()
                except Exception:
                    pass

                txt = body.decode("utf-8", "replace")
                n=0
                def repl(m):
                    nonlocal n
                    n += 1
                    return m.group(1) + m.group(2) + "?v=" + _VSP_PIN_ASSET_V

                new_txt = _re_core.sub(repl, txt)
                new_body = new_txt.encode("utf-8")

                headers = _set("X-VSP-ASSET-REWRITE-COUNT", str(n))
                headers = _drop("Content-Length")
                headers = _set("Content-Length", str(len(new_body)))

                start_response(status, headers, exc)
                return [new_body]
            except Exception:
                headers = _set("X-VSP-ASSET-REWRITE", "mw-error")
                start_response(status, headers, exc)
                return it

    # wrap the most likely callable(s) used by gunicorn
    for _name in ("application", "app"):
        _obj = globals().get(_name)
        if _obj is not None:
            try:
                globals()[_name] = _VspAssetPinMiddleware(_obj)
            except Exception:
                pass
except Exception:
    pass
# --- end VSP_P2_WSGI_MIDDLEWARE_PIN_ASSET_V_V3 ---
'''
block = block.replace("__PIN__", pin)
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended WSGI middleware v3")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

echo "[INFO] restarting $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== header proof (must show X-VSP-ASSET-REWRITE: mw) =="
curl -sSI "$BASE/runs" | egrep -i 'x-vsp-asset-rewrite|x-vsp-asset-rewrite-count|x-vsp-asset-v|content-type' || true

echo "== quick verify core basenames per tab (must all be v=$PIN) =="
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" \
    | grep -oE '(vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+)' \
    | sort -u || true
done

echo "== unique v across tabs (core only) =="
(
  for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
    curl -sS "$BASE$pth" \
      | grep -oE 'vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+' \
      | sed -n 's/.*?v=//p' || true
  done
) | sort -u | sed 's/^/[V] /'
