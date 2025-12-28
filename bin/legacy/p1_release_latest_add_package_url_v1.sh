#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_relpkgurl_${TS}"
echo "[BACKUP] ${WSGI}.bak_relpkgurl_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_LATEST_ADD_PKG_URL_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# add a small helper near the release_latest intercept (best-effort: append right after existing REALFILE intercept marker)
anchor = "VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V2_SAFEAPPEND"
i = s.find(anchor)
if i < 0:
    raise SystemExit("[ERR] cannot find release_latest intercept marker V2_SAFEAPPEND")

ins = r'''
# ===================== VSP_P1_RELEASE_LATEST_ADD_PKG_URL_V1 =====================
try:
    import urllib.parse
except Exception:
    urllib = None
# ===================== /VSP_P1_RELEASE_LATEST_ADD_PKG_URL_V1 =====================
'''

# append helper once, near marker
s2 = s[:i] + ins + s[i:]

# now inject package_url into the 'out = {...}' dict (the one containing source_json: src)
pat = r'(out\s*=\s*\{\s*[^}]*?"source_json"\s*:\s*src,\s*)(\}\s*)'
m = re.search(pat, s2, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate out-dict in release_latest intercept (source_json: src)")

add = r'''
        "package_url": ("/api/vsp/release_pkg_download?path=" + (urllib.parse.quote(pkg) if (pkg and urllib and hasattr(urllib,"parse")) else pkg)) if pkg else "",
'''
s2 = re.sub(pat, r'\1' + add + r'\2', s2, count=1, flags=re.S)

p.write_text(s2, encoding="utf-8")
print("[OK] injected package_url into /api/vsp/release_latest")
PY

python3 -m py_compile "$WSGI"
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify package_url =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("package_url=", j.get("package_url")); print("release_pkg=", j.get("release_pkg"))'
echo "[DONE] package_url added."
