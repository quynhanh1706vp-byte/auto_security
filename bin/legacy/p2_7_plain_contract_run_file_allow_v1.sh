#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
JS="static/js/vsp_dashboard_luxe_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p2_7_plain_${TS}"
cp -f "$JS"  "${JS}.bak_p2_7_plain_${TS}"
echo "[BACKUP] ${APP}.bak_p2_7_plain_${TS}"
echo "[BACKUP] ${JS}.bak_p2_7_plain_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys

app = Path("vsp_demo_app.py")
s = app.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_7_RUN_FILE_ALLOW_PLAIN_V1"
if MARK not in s:
    # Try to locate run_file_allow handler (best-effort)
    # We'll inject a small block near where it builds the JSON response dict.
    # Look for "def api_vsp_run_file_allow" or route string.
    m = re.search(r"(def\s+api_vsp_run_file_allow\s*\(.*?\):)", s)
    if not m:
        m = re.search(r"(@app\.get\(\s*['\"]/api/vsp/run_file_allow['\"]\s*\))", s)
    if not m:
        print("[ERR] cannot locate run_file_allow handler in vsp_demo_app.py", file=sys.stderr)
        sys.exit(2)

    # naive injection: after function signature line, add plain param logic hook comment
    # then later we'll patch response packing by matching a return jsonify({...})
    # We'll patch by inserting just before the final return jsonify(resp)
    # common patterns: return jsonify(resp) / return flask.jsonify(resp)
    # First, ensure a "plain" var exists near top of function (right after signature).
    # Insert right after the def line end.
    insert_pos = m.end()
    s = s[:insert_pos] + f"\n    # {MARK}\n    plain = str(request.args.get('plain','0')).lower() in ('1','true','yes')\n" + s[insert_pos:]

    # Now patch any "return jsonify(resp)" inside that handler by unwrapping when plain and findings_unified.json
    # We'll match first occurrence of `return jsonify(resp)` after the marker.
    idx = s.find(MARK)
    tail = s[idx:idx+20000]

    # find a return jsonify(...) statement
    r = re.search(r"\n(\s*)return\s+(?:jsonify|flask\.jsonify)\(\s*(\w+)\s*\)\s*\n", tail)
    if not r:
        print("[ERR] cannot find return jsonify(respVar) near handler to patch", file=sys.stderr)
        sys.exit(2)

    indent = r.group(1)
    resp_var = r.group(2)

    patch = f"""
{indent}# {MARK} plain contract: for findings_unified.json, return {{meta,findings}} when plain=1
{indent}try:
{indent}    _path = str(request.args.get('path','') or '')
{indent}    if plain and _path.endswith('findings_unified.json') and isinstance({resp_var}, dict) and {resp_var}.get('ok') is True:
{indent}        return jsonify({{'meta': {resp_var}.get('meta') or {{}}, 'findings': {resp_var}.get('findings') or []}})
{indent}except Exception:
{indent}    pass
"""

    # insert patch just before the return line we matched
    start = idx + r.start()
    end = idx + r.start()  # insert at start of return line
    s = s[:end] + patch + s[end:]

    s = "## " + MARK + "\n" + s

app.write_text(s, encoding="utf-8")
py_compile.compile(str(app), doraise=True)
print("[OK] patched vsp_demo_app.py plain contract")
PY

python3 - <<'PY'
from pathlib import Path
import re, sys

js = Path("static/js/vsp_dashboard_luxe_v1.js")
s = js.read_text(encoding="utf-8", errors="ignore")
MARK = "VSP_P2_7_LUXE_CALL_PLAIN_V1"
if MARK in s:
    print("[OK] luxe already calls plain=1")
    raise SystemExit(0)

# Replace the findings_unified call line to add &plain=1
# Your file has: /api/vsp/run_file_allow?...&path=findings_unified.json&limit=25
pat = r"(/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=findings_unified\.json&limit=\d+)"
m = re.search(pat, s)
if not m:
    # fallback: append &plain=1 to any run_file_allow findings_unified.json URL literal
    s2 = s.replace("path=findings_unified.json", "path=findings_unified.json&plain=1")
else:
    s2 = s.replace(m.group(1), m.group(1) + "&plain=1")

if s2 == s:
    print("[ERR] failed to patch luxe to add plain=1", file=sys.stderr)
    sys.exit(2)

s2 = "/* " + MARK + " */\n" + s2
js.write_text(s2, encoding="utf-8")
print("[OK] patched luxe to request plain=1")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  echo "[OK] restarted: $SVC (best-effort)"
fi

echo
echo "[NEXT] Verify:"
echo "  Ctrl+Shift+R /vsp5 -> should still work, and now backend supports plain=1 so JS unwrap becomes redundant."
