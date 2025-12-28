#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="wsgi_vsp_ui_gateway.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${APP}.bak_cachebust_alljs_${TS}"
cp -f "$APP" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re, sys, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_MW_CACHEBUST_ALL_JS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# ---- insert helper block near imports (safe, idempotent) ----
helper = r'''
# ===================== VSP_P1_MW_CACHEBUST_ALL_JS_V1 =====================
import re as _re

def _vsp__cachebust_url_keep_other_params(url: str, asset_v: str) -> str:
    """Ensure v=<asset_v> exists for /static/js/*.js; override old v; keep other params."""
    if not url or not asset_v:
        return url
    av = str(asset_v).strip()
    if not av:
        return url

    frag = ""
    if "#" in url:
        url, frag0 = url.split("#", 1)
        frag = "#" + frag0

    if "?" in url:
        base, qs = url.split("?", 1)
        parts = [q for q in qs.split("&") if q and not q.startswith("v=")]
        parts.append("v=" + av)
        return base + "?" + "&".join(parts) + frag
    return url + "?v=" + av + frag

def _vsp__cachebust_all_static_js(html: str, asset_v: str) -> str:
    """Rewrite every script src under /static/js/*.js to carry v=<asset_v>."""
    if not html or not asset_v:
        return html
    av = str(asset_v).strip()
    if not av:
        return html

    def repl_dq(m):
        url = m.group(1)
        fixed = _vsp__cachebust_url_keep_other_params(url, av)
        return f'src="{fixed}"'

    def repl_sq(m):
        url = m.group(1)
        fixed = _vsp__cachebust_url_keep_other_params(url, av)
        return f"src='{fixed}'"

    # src="/static/js/xxx.js" or src="/static/js/xxx.js?..."
    html = _re.sub(r'src="(/static/js/[^"\s]+?\.js)(?:\?[^"\s]*)?"', repl_dq, html)
    html = _re.sub(r"src='(/static/js/[^'\s]+?\.js)(?:\?[^'\s]*)?'", repl_sq, html)
    return html
# ===================== /VSP_P1_MW_CACHEBUST_ALL_JS_V1 =====================
'''

# try to place helper after the last import in the first ~140 lines
lines = s.splitlines(True)
import_end = None
for i in range(min(len(lines), 140)):
    if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', lines[i]):
        import_end = i

if import_end is None:
    # fallback: insert at top
    insert_pos = 0
else:
    insert_pos = import_end + 1

lines.insert(insert_pos, helper + "\n")
s2 = "".join(lines)

# ---- insert call in HTML rewrite flow (prefer existing MW2 / autorid anchor) ----
lines2 = s2.splitlines(True)

def find_anchor():
    # strongest anchor: existing autorid rewrite line
    for i, ln in enumerate(lines2):
        if "vsp_tabs4_autorid_v1.js" in ln:
            return i
    # second: MW2 marker
    for i, ln in enumerate(lines2):
        if "MW2" in ln or "VSP_MW2" in ln:
            return i
    # third: a place that clearly rewrites HTML
    for i, ln in enumerate(lines2):
        if "text/html" in ln and ("set_data" in "".join(lines2[i:i+80]) or "get_data" in "".join(lines2[i:i+80])):
            return i
    return None

a = find_anchor()
if a is None:
    # restore backup already created by bash caller
    print("[ERR] Could not find HTML rewrite anchor (autorid/MW2/text/html). No changes applied.")
    sys.exit(3)

indent = re.match(r'^(\s*)', lines2[a]).group(1)
call_line = indent + "html = _vsp__cachebust_all_static_js(html, asset_v)\n"

# insert call only if not already present nearby
window = "".join(lines2[max(0, a-20): min(len(lines2), a+40)])
if "_vsp__cachebust_all_static_js" not in window:
    # try to insert AFTER a line that already has html assignment near anchor
    ins = None
    for j in range(a, min(len(lines2), a+60)):
        if re.search(r'\bhtml\s*=', lines2[j]) or "vsp_tabs4_autorid_v1.js" in lines2[j]:
            ins = j + 1
            break
    if ins is None:
        ins = a + 1
    lines2.insert(ins, call_line)

out = "".join(lines2)
p.write_text(out, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

# restart if systemd exists
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl not found; restart service manually if needed."
fi

echo "[DONE] MW cache-bust all /static/js/*.js using asset_v"
