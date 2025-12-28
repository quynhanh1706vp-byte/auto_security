#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_csuite_redirect_v3_${TS}"
echo "[BACKUP] ${W}.bak_csuite_redirect_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK = "# VSP_CSUITE_REDIRECT_ALWAYS_HTML_V3"
if MARK not in s:
    block = r'''
%s
# Force /c/* to be HTML by redirecting to canonical tabs.
# This avoids collisions with any JSON/proxy/run_file_allow logic.
try:
    from flask import redirect, request
except Exception:
    redirect = None
    request = None

def _vsp_qs_keep_rid(default_rid=""):
    try:
        rid = (request.args.get("rid") or "").strip() if request else ""
    except Exception:
        rid = ""
    if not rid:
        rid = default_rid or ""
    return ("?rid="+rid) if rid else ""

def _vsp_redirect_to(path):
    qs = _vsp_qs_keep_rid("")
    return redirect(path + qs, code=302)

@app.route("/c")
@app.route("/c/")
def vsp_c_index_v3():
    return _vsp_redirect_to("/vsp5")

@app.route("/c/dashboard")
def vsp_c_dashboard_v3():
    return _vsp_redirect_to("/vsp5")

@app.route("/c/runs")
def vsp_c_runs_v3():
    return _vsp_redirect_to("/runs")

@app.route("/c/data_source")
def vsp_c_data_source_v3():
    return _vsp_redirect_to("/data_source")

@app.route("/c/settings")
def vsp_c_settings_v3():
    return _vsp_redirect_to("/settings")

@app.route("/c/rule_overrides")
def vsp_c_rule_overrides_v3():
    return _vsp_redirect_to("/rule_overrides")
''' % MARK

    # Insert near the end but BEFORE application binding if present
    m = re.search(r'(?m)^\s*application\s*=\s*', s)
    if m:
        s = s[:m.start()] + block + "\n\n" + s[m.start():]
    else:
        s = s + "\n\n" + block + "\n"

# Ensure application binding exists for gunicorn
if not re.search(r'(?m)^\s*application\s*=\s*app\s*$', s):
    s = s + "\n\n# VSP_APPLICATION_BIND_V3\napplication = app\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] gateway patched + py_compile OK")
PY

echo "== [restart best-effort] =="
if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] no passwordless sudo; run manually:"
  echo "  sudo systemctl daemon-reload && sudo systemctl restart $SVC"
fi

echo "== [smoke: /c/* must be HTML (first char '<') ] =="
for p in /c /c/dashboard /c/runs /c/data_source /c/settings /c/rule_overrides; do
  first="$(curl -fsS --connect-timeout 1 --max-time 6 "$BASE$p" | head -c 1 || true)"
  if [ "$first" != "<" ]; then
    echo "[FAIL] $p not HTML (first_char='${first:-?}')"
    exit 1
  fi
  echo "[OK] $p => HTML"
done

echo "[DONE] CSuite /c/* fixed (redirect always HTML). Ctrl+F5 once."
