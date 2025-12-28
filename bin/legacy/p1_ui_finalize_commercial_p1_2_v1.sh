#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

tpl = Path("templates")
if not tpl.is_dir():
    raise SystemExit("[ERR] templates/ not found")

css_href = '/static/css/vsp_dark_commercial_p1_2.css?v=' + str(int(time.time()))
js_src  = '/static/js/vsp_ui_keepalive_p1_2.js?v=' + str(int(time.time()))
MARK_CSS = "VSP_UI_DARK_CSS_P1_2_INJECT"
MARK_JS  = "VSP_UI_KEEPALIVE_JS_P1_2_INJECT"

# pick likely VSP templates first; fallback to all html
cands = []
for pat in ["*vsp*.html","*dashboard*.html","*data*source*.html","*settings*.html","*rule*override*.html","*runs*.html"]:
    cands += list(tpl.glob(pat))
cands = [p for p in dict.fromkeys(cands) if p.is_file()]
if not cands:
    cands = list(tpl.glob("*.html"))

patched = 0
for p in cands:
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s

    # inject CSS after <head...>
    if MARK_CSS not in s and re.search(r"<head\b", s, re.I):
        s = re.sub(r"(<head\b[^>]*>)", r"\1\n  <!-- %s -->\n  <link rel=\"stylesheet\" href=\"%s\">" % (MARK_CSS, css_href), s, count=1, flags=re.I)

    # inject JS before </body>
    if MARK_JS not in s and re.search(r"</body\s*>", s, re.I):
        s = re.sub(r"(</body\s*>)", r"  <!-- %s -->\n  <script defer src=\"%s\"></script>\n\1" % (MARK_JS, js_src), s, count=1, flags=re.I)

    if s != orig:
        p.write_text(s, encoding="utf-8")
        patched += 1

print(f"[OK] injected into templates: {patched}/{len(cands)}")
PY

echo "[OK] UI commercial polish P1.2 applied (CSS + keepalive)."
echo "[NEXT] restart UI then verify: bin/p1_ui_verify_commercial_p1_2_v1.sh"
