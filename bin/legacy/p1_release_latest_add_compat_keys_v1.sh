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
cp -f "$WSGI" "${WSGI}.bak_rellatest_compat_${TS}"
echo "[BACKUP] ${WSGI}.bak_rellatest_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V2_SAFEAPPEND"
if marker not in s:
    raise SystemExit(f"[ERR] missing marker block: {marker}")

# Find the 'out = { ... }' dict inside the V2 intercept and append compat keys before the closing brace.
# We'll locate the specific dict that contains "source_json": src to avoid accidental matches.
pat = r'(out\s*=\s*\{\s*[^}]*?"source_json"\s*:\s*src,\s*)(\}\s*)'
m = re.search(pat, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate out-dict in release_latest intercept (look for source_json: src)")

insert = r'''
        # --- compat keys for legacy UI card (expects ts/package/sha) ---
        "updated": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "ts": relj.get("release_ts","") or time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "package": pkg,
        "sha": relj.get("release_sha",""),
        "sha12": (str(relj.get("release_sha",""))[:12] if relj.get("release_sha") else ""),
        "ok_pkg": ok_pkg,
'''

s2 = re.sub(pat, r'\1' + insert + r'\2', s, count=1, flags=re.S)

# Also: if UI uses "status" text, provide alias
# Add after "release_status": ... if present
s2 = re.sub(
    r'("release_status"\s*:\s*"OK"\s*if\s*ok_pkg\s*else\s*"STALE"\s*,)',
    r'\1\n                "status": "OK" if ok_pkg else "NO PKG",',
    s2,
    count=1
)

p.write_text(s2, encoding="utf-8")
print("[OK] added compat keys: ts/package/sha/status (release_latest)")
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== quick verify payload has ts/package/sha =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin);
print("release_status=",j.get("release_status"),"pkg_exists=",j.get("release_pkg_exists"));
print("ts=",j.get("ts")); print("package=",j.get("package")); print("sha12=", (j.get("sha") or "")[:12])'
echo "[DONE] compat patch applied."
