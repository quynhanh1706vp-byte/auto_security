#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sort

# 0) pick pinned from systemd env
PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd ($SVC)"; exit 2
fi
echo "[OK] pinned VSP_ASSET_V=$PIN"

# 1) rollback to backup that existed before the broken patch
BKP="wsgi_vsp_ui_gateway.py.bak_force_assetv_20251224_123955"
if [ ! -f "$BKP" ]; then
  # fallback: pick newest backup
  BKP="$(ls -1t wsgi_vsp_ui_gateway.py.bak_force_assetv_* 2>/dev/null | head -n 1 || true)"
fi
if [ -z "${BKP:-}" ] || [ ! -f "$BKP" ]; then
  echo "[ERR] cannot locate backup wsgi_vsp_ui_gateway.py.bak_force_assetv_*"; exit 2
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.broken_before_rescue_${TS}" 2>/dev/null || true
cp -f "$BKP" "$W"
echo "[OK] restored $W from $BKP (saved broken as ${W}.broken_before_rescue_${TS})"

# 2) append safe pinned block at EOF (top-level only)
python3 - "$W" "$PIN" <<'PY'
import sys, re
from pathlib import Path

fn=sys.argv[1]; pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_FORCE_ASSET_V_PINNED_RENDER_TEMPLATE_V2"
if marker in s:
    print("[OK] marker already present; skip append")
    sys.exit(0)

block = f'''

# --- {marker} ---
# Commercial+ strict: force deterministic asset_v across ALL templates/pages.
try:
    import os as _os
    _VSP_PIN_ASSET_V = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS") or "{pin}"

    # 1) context_processor (covers templates that read {{'{{'}} asset_v {{'}}'}})
    try:
        @app.context_processor
        def _vsp_asset_v_ctx_v2():
            return {{"asset_v": _VSP_PIN_ASSET_V}}
    except Exception:
        pass

    # 2) hard override render_template used in this module
    try:
        from flask import templating as _templ
        _orig_rt = _templ.render_template

        def _vsp_render_template_pinned_v2(template_name_or_list, **context):
            context["asset_v"] = _VSP_PIN_ASSET_V
            return _orig_rt(template_name_or_list, **context)

        _templ.render_template = _vsp_render_template_pinned_v2
        globals()["render_template"] = _vsp_render_template_pinned_v2
    except Exception:
        pass

    # 3) last resort: rewrite any /static/*.js|css?v=... inside HTML
    try:
        import re as _re
        _re_asset = _re.compile(r'(/static/[^"\\'\\s>]+\\.(?:js|css))(?:\\?[^"\\'\\s>]*)?')
        @app.after_request
        def _vsp_after_request_pin_assets_v2(resp):
            try:
                ctype=(resp.headers.get("Content-Type") or "").lower()
                if "text/html" not in ctype:
                    return resp
                data = resp.get_data()
                if not data:
                    return resp
                txt = data.decode("utf-8","replace")

                def repl(m):
                    path = m.group(1)
                    return f"{path}?v={_VSP_PIN_ASSET_V}"

                new_txt = _re_asset.sub(repl, txt)
                if new_txt != txt:
                    resp.set_data(new_txt.encode("utf-8"))
                    resp.headers.pop("Content-Length", None)
                return resp
            except Exception:
                return resp
    except Exception:
        pass
except Exception:
    pass
# --- end {marker} ---
'''
p.write_text(s + block, encoding="utf-8")
print("[OK] appended pinned asset_v block at EOF")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

echo "[INFO] restarting $SVC"
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== quick verify core basenames per tab (must all be v=$PIN) =="
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" \
    | grep -oE '(vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+)' \
    | sort -u || true
done

echo "== unique v across tabs =="
( for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
    curl -sS "$BASE$pth" | grep -oE '\?v=[0-9A-Za-z_]+' || true
  done ) | sed 's/^?v=//' | sort -u | sed 's/^/[V] /'
