#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp; need grep; need sed
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "[ERR] need curl"; exit 2; }
command -v sudo >/dev/null 2>&1 || true

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$W" ]  || { echo "[ERR] missing $W"; exit 2; }

cp -f "$JS" "${JS}.bak_p0fix_${TS}"
cp -f "$W"  "${W}.bak_p0fix_${TS}"
echo "[BACKUP] ${JS}.bak_p0fix_${TS}"
echo "[BACKUP] ${W}.bak_p0fix_${TS}"

echo "== [1] Patch JS (rid + BASE + run_file_allow + Open button) =="
python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# (A) Fix broken "const = (...)" -> "const rid = (...)"
s, n_const_blank = re.subn(r'(?m)^\s*const\s*=\s*\(', '  const rid = (', s)

# (B) Fix "rid = (...)" (bare assignment) -> "const rid = (...)"
# Only when line starts with rid assignment (avoid touching "obj.rid =")
s, n_rid_bare = re.subn(r'(?m)^\s*rid\s*=\s*\(', '  const rid = (', s)

# (C) Ensure BASE defined (inject once)
if not re.search(r'(?m)^\s*const\s+BASE\s*=\s*', s):
    inject = (
        '  const BASE = (window.__VSP_UI_BASE || window.VSP_UI_BASE || window.__VSP_BASE || location.origin)\n'
        '    .toString().replace(/\\/$/, "");\n\n'
    )
    # Prefer inject after "use strict"; else after first "{"
    if '"use strict"' in s:
        s = re.sub(r'("use strict";\s*\n)', r'\1' + inject, s, count=1)
    else:
        # insert after first opening brace of IIFE/module-ish
        m = re.search(r'\{\s*\n', s)
        if m:
            s = s[:m.end()] + inject + s[m.end():]
        else:
            s = inject + s

# (D) Replace /api/vsp/run_file -> /api/vsp/run_file_allow (avoid double)
s, n_runfile = re.subn(r'/api/vsp/run_file(?!_allow)', '/api/vsp/run_file_allow', s)

# (E) If it tries to GET "reports/" to compute overall, make it a real json file path
# (best-effort; keep inside try/catch)
s = re.sub(r'api\.runFile\(\s*rid\s*,\s*["\']reports/["\']\s*\)',
           'api.runFile(rid, "reports/run_gate_summary.json")', s)

# (F) Change the "Open" button to UI route instead of API (avoid 404/deny)
# Replace href: api.runFile(rid,"reports/") with href: BASE+"/runs?rid="+encodeURIComponent(rid)
s = re.sub(
    r'href\s*:\s*api\.runFile\(\s*rid\s*,\s*["\']reports/["\']\s*\)\s*,\s*text\s*:\s*["\']Open\s*["\']',
    'href: (BASE + "/runs?rid=" + encodeURIComponent(rid)), text:"Open"',
    s
)

# (G) If rid still not declared anywhere (paranoia), fail early
if not re.search(r'(?m)^\s*(const|let|var)\s+rid\s*=', s):
    raise SystemExit("PATCH FAIL: could not ensure 'const rid =' exists")

p.write_text(s, encoding="utf-8")
print("patched:", p)
print("n_const_blank=", n_const_blank, "n_rid_bare=", n_rid_bare, "n_runfile=", n_runfile)
PY

echo "== [2] node --check JS =="
if ! node --check "$JS" >/dev/null 2>&1; then
  echo "[ERR] JS syntax still broken. Showing first error:"
  node --check "$JS" 2>&1 | head -n 40
  echo "[HINT] Reverting JS backup..."
  cp -f "${JS}.bak_p0fix_${TS}" "$JS"
  exit 2
fi
echo "[OK] JS syntax OK"

echo "== [3] Patch gateway: add /c/* redirects + application binding =="
python3 - <<'PY'
from pathlib import Path
import re, sys, textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# Ensure flask import has redirect
m = re.search(r'(?m)^\s*from\s+flask\s+import\s+(.+)\s*$', s)
if m:
    imports = m.group(1)
    if "redirect" not in imports:
        # add redirect near request if possible, else append
        if "request" in imports:
            imports2 = imports.replace("request", "request, redirect")
        else:
            imports2 = imports + ", redirect"
        s = s[:m.start(1)] + imports2 + s[m.end(1):]
else:
    # If no import line found, don't risk breaking; just rely on existing redirect maybe.
    pass

# Insert /c/* routes if missing
if "/c/dashboard" not in s:
    block = textwrap.dedent("""
    # --- P0: commercial /c/* route compatibility (redirect to 5-tab suite) ---
    @app.route("/c")
    def __c_root():
        qs = request.query_string.decode()
        return redirect("/vsp5" + (("?" + qs) if qs else ""), code=302)

    @app.route("/c/dashboard")
    def __c_dashboard():
        qs = request.query_string.decode()
        return redirect("/vsp5" + (("?" + qs) if qs else ""), code=302)

    @app.route("/c/runs")
    def __c_runs():
        qs = request.query_string.decode()
        return redirect("/runs" + (("?" + qs) if qs else ""), code=302)

    @app.route("/c/data_source")
    def __c_data_source():
        qs = request.query_string.decode()
        return redirect("/data_source" + (("?" + qs) if qs else ""), code=302)

    @app.route("/c/settings")
    def __c_settings():
        qs = request.query_string.decode()
        return redirect("/settings" + (("?" + qs) if qs else ""), code=302)

    @app.route("/c/rule_overrides")
    def __c_rule_overrides():
        qs = request.query_string.decode()
        return redirect("/rule_overrides" + (("?" + qs) if qs else ""), code=302)
    # --- end /c/* redirects ---
    """).strip("\n") + "\n\n"

    # place after app creation (best-effort)
    mm = re.search(r'(?m)^\s*app\s*=\s*Flask\([^\n]*\)\s*$', s)
    if mm:
        ins = mm.end()
        s = s[:ins] + "\n\n" + block + s[ins:]
    else:
        # fallback: put near top (after imports)
        im = re.search(r'(?m)^\s*(app\s*=)', s)
        if im:
            s = s[:im.start()] + block + s[im.start():]
        else:
            s = block + s

# Ensure gunicorn binding "application"
if not re.search(r'(?m)^\s*application\s*=\s*app\s*$', s):
    s = s.rstrip() + "\n\napplication = app\n"

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("patched:", p)
PY
echo "[OK] gateway py_compile OK"

echo "== [4] daemon-reload + restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC"

echo "== [5] wait port =="
ok=0
for i in $(seq 1 90); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null 2>&1; then
    ok=1; break
  fi
  sleep 0.2
done
if [ "$ok" -ne 1 ]; then
  echo "[ERR] UI not up at $BASE"
  systemctl status "$SVC" --no-pager || true
  echo "---- tail error log ----"
  tail -n 80 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log 2>/dev/null || true
  exit 2
fi
echo "[OK] UI up: $BASE"

echo "== [6] Quick smoke =="
echo "-- rule_overrides_v1 --"
curl -fsS "$BASE/api/vsp/rule_overrides_v1" | head -c 240; echo
echo "-- runs --"
curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | head -c 240; echo

echo "[DONE] open: $BASE/vsp5  (and /c/dashboard now redirects)"
