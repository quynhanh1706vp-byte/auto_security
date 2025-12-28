#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

# 1) snapshot
cp -f "$APP" "${APP}.bak_reports_inject_${TS}"
echo "[BACKUP] ${APP}.bak_reports_inject_${TS}"

# 2) fetch /reports into temp file (avoid heredoc stdin conflicts)
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
curl -fsS "$BASE/reports" > "$TMP"

python3 - "$TMP" <<'PY'
from pathlib import Path
import re, sys, time, py_compile

tmp_html = Path(sys.argv[1])
html = tmp_html.read_text(encoding="utf-8", errors="replace")

tpl_dir = Path("templates")
MARK="VSP_P1_TABS4_AUTORID_NODASH_V1"
inject = '\n<!-- '+MARK+' -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{ asset_v|default(\'\') }}"></script>\n'

# ---------- A) Patch templates that look like reports pages ----------
title = ""
m = re.search(r"<title>(.*?)</title>", html, re.I|re.S)
if m:
    title = (m.group(1) or "").strip()

targets=[]
for p in tpl_dir.rglob("*.html"):
    name = p.name.lower()
    t = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_tabs4_autorid_v1.js" in t:
        continue
    # heuristic: template name contains report OR html title match
    if ("report" in name) or ("runs_reports" in name) or (title and title in t):
        targets.append(p)

targets = sorted(set(targets))
patched = 0
for p in targets:
    t = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_tabs4_autorid_v1.js" in t:
        continue
    if "</body>" in t:
        t2 = t.replace("</body>", inject + "</body>", 1)
    else:
        t2 = t + inject
    p.write_text(t2, encoding="utf-8")
    print("[OK] injected into template:", p)
    patched += 1

if patched == 0:
    print("[INFO] no template patched (maybe /reports is inline HTML).")

# ---------- B) Add after_request injector for /reports ONLY (fallback) ----------
app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="replace")
MARK2="VSP_P1_REPORTS_AFTER_REQUEST_INJECT_AUTORID_V1B"

if MARK2 not in s:
    block = r'''
# ===================== VSP_P1_REPORTS_AFTER_REQUEST_INJECT_AUTORID_V1B =====================
@app.after_request
def _vsp_after_request_reports_inject_autorid(resp):
    try:
        p = request.path or ""
    except Exception:
        return resp
    if p != "/reports":
        return resp
    try:
        ct = (resp.headers.get("Content-Type") or "").lower()
    except Exception:
        ct = ""
    if "text/html" not in ct:
        return resp
    try:
        body = resp.get_data(as_text=True)
    except Exception:
        return resp
    if "vsp_tabs4_autorid_v1.js" in body:
        return resp
    # cache-bust uses asset_v (context processor already added earlier)
    tag = '\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{ asset_v|default(\'\') }}"></script>\n'
    if "</body>" in body:
        body = body.replace("</body>", tag + "</body>", 1)
    else:
        body = body + tag
    try:
        resp.set_data(body)
        # adjust content-length if present
        resp.headers.pop("Content-Length", None)
    except Exception:
        return resp
    return resp
# ===================== /VSP_P1_REPORTS_AFTER_REQUEST_INJECT_AUTORID_V1B =====================
'''.strip() + "\n"

    s = s.rstrip() + "\n\n" + block
    app.write_text(s, encoding="utf-8")
    py_compile.compile(str(app), doraise=True)
    print("[OK] patched vsp_demo_app.py:", MARK2)
else:
    print("[OK] vsp_demo_app.py already has:", MARK2)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== re-smoke /reports contains autorid js? =="
curl -sS "$BASE/reports" | grep -q "vsp_tabs4_autorid_v1.js" \
  && echo "[OK] /reports has autorid js" \
  || echo "[WARN] /reports still missing autorid js (unexpected)"

