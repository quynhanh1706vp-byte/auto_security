#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TPL_DIR="templates"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_tabs4_finalize_${TS}"
echo "[BACKUP] ${W}.bak_tabs4_finalize_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

W = Path("wsgi_vsp_ui_gateway.py")
s = W.read_text(encoding="utf-8", errors="replace")

# Replace any tag building that might accidentally include braces
# Ensure the injector builds tag with pure numeric v
MARK="VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1"
if MARK not in s:
    print("[WARN] marker not found; abort to avoid patching wrong file")
    raise SystemExit(2)

# Force tag line to a known-safe form
s2 = s

# 1) harden: if code accidentally leaves "{ asset_v" in HTML, we will also clean it at response time
# Insert a cleanup step inside injector: replace bad pattern in body
if "VSP_P1_GATEWAY_TABS4_CLEAN_BAD_JINJA_V1" not in s2:
    s2 = re.sub(
        r'(if\s+"vsp_tabs4_autorid_v1\.js"\s+in\s+body:\s*\n\s*return\s+resp\s*\n)',
        r'\1\n        # VSP_P1_GATEWAY_TABS4_CLEAN_BAD_JINJA_V1\n        try:\n            body = re.sub(r\'vsp_tabs4_autorid_v1\\.js\\?v=\\{[^\\}]*\\}\', "vsp_tabs4_autorid_v1.js?v="+_vsp_gateway_asset_v(), body)\n        except Exception:\n            pass\n',
        s2,
        count=1
    )

# 2) ensure we import re in gateway block if not already
if "import re" not in s2:
    # best effort: add near top of file
    s2 = "import re\n" + s2

# 3) ensure the injected tag uses numeric v (already should, but we force replace any f-string with braces)
s2 = re.sub(
    r'(tag\s*=\s*f[\'"][^\'"]*vsp_tabs4_autorid_v1\.js\?v=\{v\}[\'"])',
    r'tag = f\'\\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={_vsp_gateway_asset_v()}"></script>\\n\'',
    s2
)

W.write_text(s2, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] hardened gateway injector + cleanup bad jinja if present")
PY

# Cleanup templates: remove any old injected line that uses ?v={{ ... }}
python3 - <<'PY'
from pathlib import Path
import re

tpl_dir = Path("templates")
pat = re.compile(r'\n?<!--\s*VSP_P1_TABS4_AUTORID_NODASH_V1\s*-->\s*\n?<script[^>]*vsp_tabs4_autorid_v1\.js\?v=\{\{[^>]*</script>\s*\n?', re.I)

n=0
for p in tpl_dir.rglob("*.html"):
    t = p.read_text(encoding="utf-8", errors="replace")
    t2, k = pat.subn("\n", t)
    if k:
        p.write_text(t2, encoding="utf-8")
        n += k
        print("[OK] cleaned old template inject:", p, "count=", k)
print("[INFO] cleaned total inject blocks:", n)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify /runs has correct autorid src (NO braces) =="
curl -sS "$BASE/runs" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 3
