#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_forcecss_${TS}"
echo "[BACKUP] ${WSGI}.bak_forcecss_${TS}"

python3 - "$WSGI" <<'PY'
import re, sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P1_FORCE_DARK_CSS_ALL_PAGES_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

# heuristic: find function that returns HTML string (common pattern: return render_template_string(...) or return Response(html,...))
# We'll inject a tiny helper to ensure CSS link exists when serving HTML responses.
inject = r'''
# ''' + marker + r'''
def _vsp_force_css_once(html: str) -> str:
    try:
        if not isinstance(html, str) or "<html" not in html.lower():
            return html
        # if already has vsp_dark_commercial css, skip
        if "vsp_dark_commercial" in html:
            return html
        # best-effort: insert before </head>
        link = '<link rel="stylesheet" href="/static/css/vsp_dark_commercial_p1_2.css">'
        if "</head>" in html:
            return html.replace("</head>", link + "\n</head>", 1)
        return html
    except Exception:
        return html
'''

# place helper near top (after imports)
m=re.search(r'(?m)^\s*(from\s+\w+|import\s+\w+)', s)
if not m:
    # fallback prepend
    s = inject + "\n" + s
else:
    # insert after first import block
    # find end of initial import section (blank line after)
    m2 = re.search(r'(?s)\A(.*?\n)\n', s)
    if m2:
        s = m2.group(1) + inject + "\n" + s[m2.end():]
    else:
        s = inject + "\n" + s

# Now wrap returns of HTML in routes: replace "return html" to "return _vsp_force_css_once(html)" when obvious
# We'll do a conservative replace for patterns "return HTML" where variable name is html/page_html/resp_html
s2 = re.sub(r'(?m)^\s*return\s+([a-zA-Z_]\w*(?:_html|html))\s*$',
            r'return _vsp_force_css_once(\1)', s)
# Also handle render_template_string(...) / render_template(...)
s2 = re.sub(r'(?m)^\s*return\s+(render_template(?:_string)?\(.+\))\s*$',
            r'return _vsp_force_css_once(\1)', s2)

p.write_text(s2, encoding="utf-8")
print("[OK] patched: force dark css when missing")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] $SVC not active; restart manually if needed"
fi

echo "== verify /runs CSS now present? =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/runs" | grep -oE '/static/css/[^"'\'' >]+' | sed 's/[?].*$//' | sort -u
