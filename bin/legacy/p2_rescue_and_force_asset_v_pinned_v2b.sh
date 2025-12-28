#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sort

PIN="$(sudo systemctl show "$SVC" -p Environment --no-pager | tr ' ' '\n' | sed -n 's/^VSP_ASSET_V=//p' | head -n 1 || true)"
if [ -z "${PIN:-}" ]; then
  echo "[ERR] cannot read VSP_ASSET_V from systemd ($SVC)"; exit 2
fi
echo "[OK] pinned VSP_ASSET_V=$PIN"

# restore from latest bak_force_assetv if exists (safe)
BKP="$(ls -1t wsgi_vsp_ui_gateway.py.bak_force_assetv_* 2>/dev/null | head -n 1 || true)"
TS="$(date +%Y%m%d_%H%M%S)"
if [ -n "${BKP:-}" ] && [ -f "$BKP" ]; then
  cp -f "$W" "${W}.pre_rescue_${TS}" 2>/dev/null || true
  cp -f "$BKP" "$W"
  echo "[OK] restored $W from $BKP (saved previous as ${W}.pre_rescue_${TS})"
else
  echo "[WARN] no bak_force_assetv found; keep current $W"
fi

python3 - "$W" "$PIN" <<'PY'
import sys
from pathlib import Path

fn=sys.argv[1]; pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_FORCE_ASSET_V_PINNED_RENDER_TEMPLATE_V2B"
if marker in s:
    print("[OK] marker already present; nothing to do")
    sys.exit(0)

# IMPORTANT: no outer f-string; use placeholder replacement to avoid NameError.
block = r'''
# --- VSP_P2_FORCE_ASSET_V_PINNED_RENDER_TEMPLATE_V2B ---
# Commercial+ strict: deterministic asset_v across ALL pages.
try:
    import os as _os
    _VSP_PIN_ASSET_V = _os.environ.get("VSP_ASSET_V") or _os.environ.get("VSP_RELEASE_TS") or "__PIN__"

    # (1) context_processor for templates using {{ asset_v }}
    try:
        @app.context_processor
        def _vsp_asset_v_ctx_v2b():
            return {"asset_v": _VSP_PIN_ASSET_V}
    except Exception:
        pass

    # (2) override render_template used by this module
    try:
        from flask import templating as _templ
        _orig_rt = _templ.render_template
        def _vsp_render_template_pinned_v2b(template_name_or_list, **context):
            context["asset_v"] = _VSP_PIN_ASSET_V
            return _orig_rt(template_name_or_list, **context)
        _templ.render_template = _vsp_render_template_pinned_v2b
        globals()["render_template"] = _vsp_render_template_pinned_v2b
    except Exception:
        pass

    # (3) strict HTML rewrite: force core basenames to pinned v=
    try:
        import re as _re
        _CORE = (
            "vsp_bundle_tabs5_v1.js",
            "vsp_dashboard_luxe_v1.js",
            "vsp_tabs4_autorid_v1.js",
            "vsp_topbar_commercial_v1.js",
        )
        _re_core = _re.compile(r'(?:' + '|'.join([_re.escape(x) for x in _CORE]) + r')\?v=[0-9A-Za-z_]+')
        _re_anycore = _re.compile(r'(' + '|'.join([_re.escape(x) for x in _CORE]) + r')(\?[^"\'\s>]*)?')

        @app.after_request
        def _vsp_after_request_pin_assets_v2b(resp):
            try:
                ctype=(resp.headers.get("Content-Type") or "").lower()
                if "text/html" not in ctype:
                    return resp
                data = resp.get_data()
                if not data:
                    return resp
                txt = data.decode("utf-8","replace")

                # Replace any existing ?v=... for core files
                for core in _CORE:
                    txt = _re.sub(r'%s\?v=[0-9A-Za-z_]+' % _re.escape(core),
                                  '%s?v=%s' % (core, _VSP_PIN_ASSET_V),
                                  txt)

                # Ensure core files without ?v also get pinned
                def repl(m):
                    core = m.group(1)
                    return '%s?v=%s' % (core, _VSP_PIN_ASSET_V)
                txt2 = _re_anycore.sub(repl, txt)

                if txt2 != txt:
                    resp.set_data(txt2.encode("utf-8"))
                    resp.headers.pop("Content-Length", None)
                return resp
            except Exception:
                return resp
    except Exception:
        pass
except Exception:
    pass
# --- end VSP_P2_FORCE_ASSET_V_PINNED_RENDER_TEMPLATE_V2B ---
'''
block = block.replace("__PIN__", pin)

p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended pinned asset_v block (V2b)")
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

echo "== unique v across tabs (core only) =="
(
  for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
    curl -sS "$BASE$pth" \
      | grep -oE 'vsp_(bundle_tabs5|dashboard_luxe|tabs4_autorid|topbar_commercial)_v1\.js\?v=[0-9A-Za-z_]+' \
      | sed -n 's/.*?v=//p' || true
  done
) | sort -u | sed 's/^/[V] /'
