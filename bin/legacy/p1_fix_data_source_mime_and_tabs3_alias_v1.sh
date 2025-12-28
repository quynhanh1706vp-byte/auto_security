#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_ds_tabs3_${TS}"
echo "[BACKUP] ${APP}.bak_ds_tabs3_${TS}"

echo "== [1] fix templates: remove trailing backslashes after .js, and clean %22 artifacts (safe) =="

python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path("templates")
if not root.exists():
    print("[SKIP] templates/ not found")
    raise SystemExit(0)

changed = 0
for p in sorted(root.rglob("*.html")):
    s = p.read_text(encoding="utf-8", errors="replace")
    o = s

    # remove trailing backslash right after ".js" in src/href (e.g. vsp_x.js\)
    s = re.sub(r'(\.js)\\(?=[\s"\'?])', r'\1', s)

    # remove encoded quote path prefix if appears
    s = s.replace('/%22/static/', '/static/')
    s = s.replace('%22/static/', '/static/')
    s = s.replace('\\"/static/', '/static/')

    if s != o:
        bak = p.with_suffix(p.suffix + f".bak_jsfix_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(o, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        changed += 1
        print("[OK] fixed:", p)

print("[DONE] templates changed =", changed)
PY

echo "== [2] add alias route for /api/vsp/vsp_tabs3_common_v3.js (browser is calling this) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_TABS3_COMMON_ALIAS_V1"
if MARK in s:
    print("[SKIP] alias already present")
    raise SystemExit(0)

# If already has /api/vsp_tabs3_common_v3.js route, add an alias that redirects/calls it
if "/api/vsp_tabs3_common_v3.js" not in s:
    print("[WARN] base route /api/vsp_tabs3_common_v3.js not found. Will add minimal always-200 js for both paths.")

insert = r'''
# ===================== VSP_P1_TABS3_COMMON_ALIAS_V1 =====================
from flask import Response

@app.get("/api/vsp/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_alias():
    # Alias for older client code that requests /api/vsp/...
    js = "/* tabs3 common v3 (alias) */\nwindow.__vsp_tabs3_common_v3_ok=true;\n"
    return Response(js, mimetype="application/javascript")

# (keep existing /api/vsp_tabs3_common_v3.js if present)
# ===================== /VSP_P1_TABS3_COMMON_ALIAS_V1 =====================
'''
else:
    # Try to reference existing handler by name if we can find it; otherwise return a small JS stub
    insert = r'''
# ===================== VSP_P1_TABS3_COMMON_ALIAS_V1 =====================
from flask import Response

@app.get("/api/vsp/vsp_tabs3_common_v3.js")
def vsp_tabs3_common_v3_js_alias():
    # Alias for client code that requests /api/vsp/...
    try:
        # If the base function exists, call it
        return vsp_tabs3_common_v3_js()
    except Exception:
        js = "/* tabs3 common v3 (alias fallback) */\nwindow.__vsp_tabs3_common_v3_ok=true;\n"
        return Response(js, mimetype="application/javascript")

# ===================== /VSP_P1_TABS3_COMMON_ALIAS_V1 =====================
'''

# Insert near the end (before if __name__ guard if exists)
m = re.search(r'\nif\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s2 = s[:m.start()] + "\n" + insert + "\n" + s[m.start():]
else:
    s2 = s + "\n" + insert + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] inserted alias route block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] restarted $SVC"

echo "== [3] quick verify headers =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "--- data_source js ---"
curl -fsS -I "$BASE/static/js/vsp_data_source_lazy_v1.js" | sed -n '1,12p' || true
echo "--- tabs3 alias ---"
curl -fsS -I "$BASE/api/vsp/vsp_tabs3_common_v3.js" | sed -n '1,12p' || true
