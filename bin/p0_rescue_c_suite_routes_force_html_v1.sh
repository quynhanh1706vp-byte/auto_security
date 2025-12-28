#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "[ERR] need curl"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_csuite_html_${TS}"
echo "[BACKUP] ${W}.bak_csuite_html_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

BEGIN = "# VSP_CSUITE_FORCE_HTML_V1_BEGIN"
END   = "# VSP_CSUITE_FORCE_HTML_V1_END"

block = r'''
# VSP_CSUITE_FORCE_HTML_V1_BEGIN
def _vsp__csuite_html(active_tab="dashboard"):
    """
    Force /c/* to return HTML (csuite). Prevent accidental routing to run_file_allow.
    """
    try:
        av = globals().get("VSP_ASSET_V", None)
        if not av:
            import time
            av = str(int(time.time()))
    except Exception:
        av = "1"

    # Minimal HTML shell. JS will render content.
    # NOTE: keep it light; no heavy DOM. All safe to serve for commercial.
    html = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>VSP • Commercial</title>
</head>
<body data-vsp-suite="csuite" data-vsp-tab="{active_tab}">
  <div id="vsp-root"></div>

  <!-- bootstrap bundle (tabs + topbar injections) -->
  <script src="/static/js/vsp_bundle_tabs5_v1.js?v={av}" defer></script>
  <script src="/static/js/vsp_tabs4_autorid_v1.js?v={av}" defer></script>

  <!-- data filler for 5 tabs (must be syntax-clean) -->
  <script src="/static/js/vsp_fill_real_data_5tabs_p1_v1.js?v={av}" defer></script>
</body>
</html>"""
    return html

def _vsp__csuite_resp(active_tab="dashboard"):
    try:
        from flask import Response
        return Response(_vsp__csuite_html(active_tab), mimetype="text/html")
    except Exception:
        # fallback: still return HTML string
        return _vsp__csuite_html(active_tab)

# Force explicit /c/* endpoints (more specific than /c/<path:...>)
@app.route("/c", methods=["GET"])
def vsp_c_root():
    return redirect("/c/dashboard", code=302)

@app.route("/c/dashboard", methods=["GET"])
def vsp_c_dashboard():
    return _vsp__csuite_resp("dashboard")

@app.route("/c/runs", methods=["GET"])
def vsp_c_runs():
    return _vsp__csuite_resp("runs")

@app.route("/c/data_source", methods=["GET"])
def vsp_c_data_source():
    return _vsp__csuite_resp("data_source")

@app.route("/c/settings", methods=["GET"])
def vsp_c_settings():
    return _vsp__csuite_resp("settings")

@app.route("/c/rule_overrides", methods=["GET"])
def vsp_c_rule_overrides():
    return _vsp__csuite_resp("rule_overrides")
# VSP_CSUITE_FORCE_HTML_V1_END
'''.lstrip("\n")

if BEGIN in s and END in s:
    s = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END), block.strip("\n"), s, flags=re.S)
else:
    # Insert near the end, but BEFORE any "if __name__ == '__main__'" guard if present.
    m = re.search(r"(?m)^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", s)
    if m:
        s = s[:m.start()] + "\n\n" + block + "\n\n" + s[m.start():]
    else:
        s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")

# compile check
py_compile.compile(str(p), doraise=True)
print("[OK] injected/updated CSuite force HTML block")
PY

echo "== [Restart] =="
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl restart "$SVC"

echo "== [Wait port] =="
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/healthz" >/dev/null 2>&1; then
    echo "[OK] UI up: $BASE"
    break
  fi
  sleep 0.2
done

echo "== [Smoke content-type + first char must be '<'] =="
for p in /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  body="$(curl -fsS --connect-timeout 1 --max-time 4 "$BASE$p?rid=$RID" | head -c 1 || true)"
  if [ "$body" != "<" ]; then
    echo "[FAIL] $p not HTML (first_char='$body')"
    curl -fsS --connect-timeout 1 --max-time 4 "$BASE$p?rid=$RID" | head -n 3 || true
    exit 1
  fi
  echo "[OK] $p => HTML"
done

echo "[DONE] CSuite routes forced to HTML. Now Ctrl+F5."
