#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

cp -f "$W" "${W}.bak_csuite_nodup_${TS}"
echo "[BACKUP] ${W}.bak_csuite_nodup_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

BEGIN="# VSP_CSUITE_FORCE_HTML_V1_BEGIN"
END  ="# VSP_CSUITE_FORCE_HTML_V1_END"

block = r'''
# VSP_CSUITE_FORCE_HTML_V1_BEGIN
def _vsp__csuite_html(active_tab="dashboard"):
    try:
        av = globals().get("VSP_ASSET_V", None)
        if not av:
            import time
            av = str(int(time.time()))
    except Exception:
        av = "1"
    html = f"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>VSP • Commercial</title>
</head><body data-vsp-suite="csuite" data-vsp-tab="{active_tab}">
<div id="vsp-root"></div>
<script src="/static/js/vsp_bundle_tabs5_v1.js?v={av}" defer></script>
<script src="/static/js/vsp_tabs4_autorid_v1.js?v={av}" defer></script>
<script src="/static/js/vsp_fill_real_data_5tabs_p1_v1.js?v={av}" defer></script>
</body></html>"""
    return html

def _vsp__csuite_resp(active_tab="dashboard"):
    try:
        from flask import Response
        return Response(_vsp__csuite_html(active_tab), mimetype="text/html")
    except Exception:
        return _vsp__csuite_html(active_tab)

def _vsp__has_rule(path: str) -> bool:
    try:
        return any(getattr(r, "rule", None) == path for r in app.url_map.iter_rules())
    except Exception:
        return False

def _vsp__add_rule_if_missing(path: str, endpoint: str, view_func):
    try:
        if _vsp__has_rule(path):
            return
        app.add_url_rule(path, endpoint=endpoint, view_func=view_func, methods=["GET"])
    except Exception:
        return

def _vsp__register_csuite_routes():
    try:
        from flask import redirect
    except Exception:
        redirect = None
    if redirect is not None:
        _vsp__add_rule_if_missing("/c", "vsp_c_root_v2", lambda: redirect("/c/dashboard", code=302))
    _vsp__add_rule_if_missing("/c/dashboard", "vsp_c_dashboard_v2", lambda: _vsp__csuite_resp("dashboard"))
    _vsp__add_rule_if_missing("/c/runs", "vsp_c_runs_v2", lambda: _vsp__csuite_resp("runs"))
    _vsp__add_rule_if_missing("/c/data_source", "vsp_c_data_source_v2", lambda: _vsp__csuite_resp("data_source"))
    _vsp__add_rule_if_missing("/c/settings", "vsp_c_settings_v2", lambda: _vsp__csuite_resp("settings"))
    _vsp__add_rule_if_missing("/c/rule_overrides", "vsp_c_rule_overrides_v2", lambda: _vsp__csuite_resp("rule_overrides"))

try:
    _vsp__register_csuite_routes()
except Exception:
    pass
# VSP_CSUITE_FORCE_HTML_V1_END
'''.lstrip("\n").strip("\n")

if BEGIN in s and END in s:
    s = re.sub(re.escape(BEGIN)+r".*?"+re.escape(END), block, s, flags=re.S)
else:
    s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] csuite block installed (no-dup)")
PY

echo "== [restart] =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  if ! sudo systemctl restart "$SVC"; then
    echo "---- status ----"
    sudo systemctl status "$SVC" -l --no-pager || true
    echo "---- journal tail ----"
    sudo journalctl -u "$SVC" -n 160 --no-pager || true
    exit 1
  fi
else
  systemctl daemon-reload || true
  systemctl restart "$SVC" || exit 1
fi

echo "== [smoke] /c/* must be HTML =="
for pth in /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  ch="$(curl -fsS --connect-timeout 1 --max-time 4 "$BASE$pth?rid=$RID" | head -c 1 || true)"
  if [ "$ch" != "<" ]; then
    echo "[FAIL] $pth not HTML (first_char='$ch')"
    exit 1
  fi
  echo "[OK] $pth => HTML"
done

echo "[DONE] Ctrl+F5 once."
