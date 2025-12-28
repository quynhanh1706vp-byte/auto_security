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

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_append_rewriter_v2c_${TS}"
echo "[BACKUP] ${W}.bak_append_rewriter_v2c_${TS}"

python3 - "$W" "$PIN" <<'PY'
import sys
from pathlib import Path

fn=sys.argv[1]; pin=sys.argv[2]
p=Path(fn)
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_FORCE_ASSET_V_HTML_REWRITER_V2C"
if marker in s:
    print("[OK] marker already present; skip append")
    sys.exit(0)

block = r'''
# --- VSP_P2_FORCE_ASSET_V_HTML_REWRITER_V2C ---
# Fix: rewrite full path "/static/js/<core>.js?v=..." (V2b only matched basename).
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

    # Match /static/js/<core>[?anything] OR /static/<core>
    _re_full = _re.compile(
        r'(/static/(?:js|css)/)(' + '|'.join([_re.escape(x) for x in _CORE]) + r')(?:\?[^"\'\s>]*)?'
    )
    _re_short = _re.compile(
        r'(/static/)(' + '|'.join([_re.escape(x) for x in _CORE]) + r')(?:\?[^"\'\s>]*)?'
    )

    @app.after_request
    def _vsp_after_request_pin_assets_v2c(resp):
        try:
            ctype=(resp.headers.get("Content-Type") or "").lower()
            if "text/html" not in ctype:
                return resp
            data = resp.get_data()
            if not data:
                return resp
            txt = data.decode("utf-8","replace")

            def repl(m):
                return m.group(1) + m.group(2) + "?v=" + _VSP_PIN_ASSET_V

            txt2 = _re_full.sub(repl, txt)
            txt2 = _re_short.sub(repl, txt2)

            if txt2 != txt:
                resp.set_data(txt2.encode("utf-8"))
                resp.headers.pop("Content-Length", None)
            return resp
        except Exception:
            return resp
except Exception:
    pass
# --- end VSP_P2_FORCE_ASSET_V_HTML_REWRITER_V2C ---
'''
block = block.replace("__PIN__", pin)
p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended V2c HTML rewriter")
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
