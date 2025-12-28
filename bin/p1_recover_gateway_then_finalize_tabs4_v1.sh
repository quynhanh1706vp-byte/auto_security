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

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_broken_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re, time, textwrap

W = Path("wsgi_vsp_ui_gateway.py")

def compiles(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# 1) find newest compiling backup
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
good = None
for p in baks:
    if compiles(p):
        good = p
        break

if good is None:
    raise SystemExit("[FATAL] No compiling backup found for wsgi_vsp_ui_gateway.py")

# 2) restore
W.write_text(good.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored from compiling backup:", good.name)

# 3) patch: make injector sanitize bad Jinja-like src and ensure injected tag uses numeric v
s = W.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_GATEWAY_TABS4_AFTER_REQUEST_INJECT_AUTORID_V1"
if MARK not in s:
    raise SystemExit("[FATAL] injector marker not found after restore (unexpected).")

# ensure `import re` exists (safe)
if not re.search(r'^\s*import\s+re\s*$', s, re.M):
    s = "import re\n" + s
    print("[OK] added import re at top")

SAN_MARK = "VSP_P1_GATEWAY_TABS4_SANITIZE_AUTORID_SRC_V1"
if SAN_MARK not in s:
    # Insert sanitize logic right after body = resp.get_data(as_text=True)
    s2, n = re.subn(
        r'(body\s*=\s*resp\.get_data\(as_text=True\)\s*\n)',
        r'\1'
        r'\n        # ' + SAN_MARK + r'\n'
        r'        # If HTML already contains a broken autorid src like ?v={ asset_v|default(...) }, sanitize it.\n'
        r'        _orig_body = body\n'
        r'        try:\n'
        r'            body = re.sub(r"vsp_tabs4_autorid_v1\.js\?v=\{[^}]*\}", f"vsp_tabs4_autorid_v1.js?v={_vsp_gateway_asset_v()}", body)\n'
        r'        except Exception:\n'
        r'            pass\n'
        r'        _changed = (body != _orig_body)\n',
        s,
        count=1
    )
    if n != 1:
        raise SystemExit("[FATAL] could not place sanitize block (pattern not found).")
    s = s2
    print("[OK] inserted sanitize block")

# Next: adjust the "already present" check so we still return the sanitized body (not skip)
# Replace:
#   if "vsp_tabs4_autorid_v1.js" in body: return resp
# with:
#   if present and changed -> set_data(body) + return; else return
def repl_present(m):
    return (
        '        if "vsp_tabs4_autorid_v1.js" in body:\n'
        '            if _changed:\n'
        '                try:\n'
        '                    resp.set_data(body)\n'
        '                    resp.headers.pop("Content-Length", None)\n'
        '                    resp.headers["Cache-Control"] = "no-store"\n'
        '                except Exception:\n'
        '                    return resp\n'
        '            return resp\n'
    )

s2, n = re.subn(
    r'\s*if\s+"vsp_tabs4_autorid_v1\.js"\s+in\s+body:\s*\n\s*return\s+resp\s*\n',
    repl_present,
    s,
    count=1
)
if n == 1:
    s = s2
    print("[OK] hardened present-check to preserve sanitized body")
else:
    print("[WARN] present-check pattern not replaced (maybe already customized).")

# Ensure injected tag uses numeric v (some versions used v variable; we force function call)
s = re.sub(
    r'tag\s*=\s*f[\'"]\\n<!--\s*VSP_P1_TABS4_AUTORID_NODASH_V1\s*-->\\n<script\s+src="/static/js/vsp_tabs4_autorid_v1\.js\?v=\{[^}]+\}"></script>\\n[\'"]',
    'tag = f\'\\n<!-- VSP_P1_TABS4_AUTORID_NODASH_V1 -->\\n<script src="/static/js/vsp_tabs4_autorid_v1.js?v={_vsp_gateway_asset_v()}"></script>\\n\'',
    s
)

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] gateway compiles after sanitize patch")

# 4) Clean templates: remove old injected Jinja-tag lines for autorid to avoid broken src in HTML
tpl_dir = Path("templates")
pat = re.compile(
    r'<!--\s*VSP_P1_TABS4_AUTORID_NODASH_V1\s*-->\s*<script[^>]*vsp_tabs4_autorid_v1\.js\?v=\{\{.*?\}\}[^>]*></script>\s*',
    re.I | re.S
)
cleaned = 0
for p in tpl_dir.rglob("*.html"):
    t = p.read_text(encoding="utf-8", errors="replace")
    t2, k = pat.subn("", t)
    if k:
        p.write_text(t2, encoding="utf-8")
        cleaned += k
        print("[OK] cleaned old autorid inject in template:", p.name, "count=", k)
print("[INFO] total template clean blocks:", cleaned)
PY

echo "[INFO] Restart service: $SVC"
systemctl restart "$SVC" 2>/dev/null || true

echo "== verify /runs autorid src (should be numeric v, no braces) =="
curl -sS "$BASE/runs" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 3 || true

echo "== verify /settings autorid src =="
curl -sS "$BASE/settings" | grep -oE 'vsp_tabs4_autorid_v1\.js[^"]*' | head -n 3 || true
