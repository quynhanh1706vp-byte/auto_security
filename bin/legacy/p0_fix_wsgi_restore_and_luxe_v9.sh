#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
JS="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$F" ]  || { echo "[ERR] missing $F"; exit 2; }
[ -f "$JS" ] || { echo "[ERR] missing $JS (run p0_dashboard_luxe_v1.sh first)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

cp -f "$F" "${F}.bak_before_restore_${TS}"
echo "[BACKUP] ${F}.bak_before_restore_${TS}"

echo "== restore latest compiling backup of wsgi (auto) =="
python3 - <<'PY'
from pathlib import Path
import py_compile, os

f = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

def ok(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

good = None
for p in baks[:1200]:
    if ok(p):
        good = p
        break

if not good:
    raise SystemExit("[ERR] cannot find any compiling backup wsgi_vsp_ui_gateway.py.bak_*")

s = good.read_text(encoding="utf-8", errors="replace")
f.write_text(s, encoding="utf-8")
print("[OK] restored from:", good.name)
PY

echo "== inject LUXE safely (triple-quote f-string; no more unterminated) =="
python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_LUXE_SAFE_INJECT_V9"
if MARK in s:
    print("[SKIP] already injected", MARK)
    raise SystemExit(0)

# 1) ensure host div appears before vsp5_root in the VSP5 HTML (best effort, pure text replace)
if 'id="vsp5_root"' in s and 'id="vsp_luxe_host"' not in s:
    s2, n = re.subn(r'(<div\s+id="vsp5_root"\s*>\s*</div>)',
                    r'<div id="vsp_luxe_host"></div>\n  \1', s, count=1)
    if n:
        s = s2
        print("[OK] inserted #vsp_luxe_host before #vsp5_root")

# 2) Fix/replace any bundle_tag assignment that mentions vsp_bundle_commercial_v2.js
#    Replace with triple-quote f-string that includes BOTH bundle + luxe in one safe block.
pattern = r'^\s*bundle_tag\s*=\s*.*vsp_bundle_commercial_v2\.js.*$'
m = re.search(pattern, s, flags=re.M)
if not m:
    # fallback: search the string literal tag itself and inject luxe right after it
    if "vsp_bundle_commercial_v2.js" not in s:
        raise SystemExit("[ERR] cannot find vsp_bundle_commercial_v2.js in wsgi to inject")
    # do a safe string-level injection (no f-string edit), before </body> of vsp5 html if present
    s2, n = re.subn(r'(</body>)',
                    r'<script src="/static/js/vsp_dashboard_luxe_v1.js?v={{ asset_v }}"></script>\n\1',
                    s, count=1)
    if n == 0:
        raise SystemExit("[ERR] cannot locate bundle_tag line nor </body> to inject")
    s = s2
    print("[OK] injected luxe before </body> (fallback)")
else:
    indent = re.match(r'^(\s*)', m.group(0)).group(1)
    repl = (
        indent + f'# {MARK}\n' +
        indent + 'bundle_tag = f"""'
                 '<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>\\n'
                 '<script src="/static/js/vsp_dashboard_luxe_v1.js?v={v}"></script>'
                 '"""\\n'
    )
    # replace ONLY that line (not multiline)
    s = s[:m.start()] + repl + s[m.end():]
    print("[OK] replaced bundle_tag with triple-quote safe version")

p.write_text(s, encoding="utf-8")
print("[DONE] wrote", p)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 must include luxe script =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3 || { echo "[ERR] luxe missing in /vsp5"; exit 2; }
echo "[DONE] Now hard refresh /vsp5: Ctrl+Shift+R"
