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
cp -f "$WSGI" "${WSGI}.bak_relpkgurl_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_relpkgurl_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_LATEST_ADD_PKG_URL_V2_ROBUSTINJECT"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

# Find the LAST release_latest intercept block (best-effort)
anchors = [
  "VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT",
  "/api/vsp/release_latest",
  "release_latest"
]
start = -1
for a in anchors:
    start = s.rfind(a)
    if start != -1:
        break
if start == -1:
    raise SystemExit("[ERR] cannot find any anchor for release_latest intercept")

# Limit search window to avoid patching elsewhere
win = s[start:start+120000]

# Find insertion point: before the FIRST 'return jsonify(out' or 'return jsonify({' in that window
m = re.search(r'\n([ \t]*)return\s+jsonify\(\s*out\s*\)', win)
if not m:
    # fallback: sometimes it's 'return jsonify(out), 200' or similar
    m = re.search(r'\n([ \t]*)return\s+jsonify\(\s*out\s*\)\s*,', win)
if not m:
    raise SystemExit("[ERR] cannot find 'return jsonify(out)' in release_latest window")

indent = m.group(1)
insert_at = start + m.start()

snippet = textwrap.dedent(f"""
{indent}# ===================== {MARK} =====================
{indent}try:
{indent}    import urllib.parse as _up
{indent}    if isinstance(out, dict):
{indent}        _pkg = out.get("release_pkg") or out.get("package") or out.get("pkg") or ""
{indent}        if _pkg:
{indent}            out["package_url"] = "/api/vsp/release_pkg_download?path=" + _up.quote(str(_pkg))
{indent}except Exception:
{indent}    pass
{indent}# ===================== /{MARK} =====================
""").rstrip("\n") + "\n"

s2 = s[:insert_at] + "\n" + snippet + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] injected", MARK, "before return jsonify(out)")
PY

python3 -m py_compile "$WSGI"
systemctl restart "$SVC" 2>/dev/null || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify package_url in release_latest =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("package_url=", j.get("package_url")); print("release_pkg=", j.get("release_pkg"))'
echo "[DONE] robust inject OK."
