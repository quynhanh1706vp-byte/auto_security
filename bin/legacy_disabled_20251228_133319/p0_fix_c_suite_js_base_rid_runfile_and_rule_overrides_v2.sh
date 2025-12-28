#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need cp
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node --check)"; exit 2; }
command -v systemctl >/dev/null 2>&1 || true

[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$JS"  "${JS}.bak_fix_v2_${TS}"
cp -f "$APP" "${APP}.bak_fix_v2_${TS}"
echo "[BACKUP] $JS  => ${JS}.bak_fix_v2_${TS}"
echo "[BACKUP] $APP => ${APP}.bak_fix_v2_${TS}"

echo "== [1] Patch JS (BASE + rid const + fallback) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

changed = 0

# (A) Fix "const = (" -> "const rid = ("
s2, n = re.subn(r'(?m)^\s*const\s*=\s*\(', 'const rid = (', s)
if n:
    s = s2; changed += n

# (B) Fix bare "rid = (" -> "const rid = ("
# Only when it's a statement at line start (avoid touching object keys etc.)
s2, n = re.subn(r'(?m)^(\s*)rid\s*=\s*\(', r'\1const rid = (', s)
if n:
    s = s2; changed += n

# (C) Make rid expression have fallback to latest.* if present.
# Replace the specific pattern: const rid = (<expr>);
m = re.search(r'(?m)^\s*const\s+rid\s*=\s*\((.+?)\)\s*;\s*$', s)
if m:
    expr = m.group(1).strip()
    # Add fallback to latest fields (safe even if latest undefined? latest is defined in your snippet)
    new_line = f'    const rid = ({expr}) || (latest.rid || latest.run_id || latest.id || "");'
    s2, n = re.subn(r'(?m)^\s*const\s+rid\s*=\s*\(.+?\)\s*;\s*$', new_line, s, count=1)
    if n:
        s = s2; changed += 1

# (D) Inject BASE if file uses BASE but doesn't define it.
uses_base = re.search(r'(?<![\w$])BASE(?![\w$])', s) is not None
has_base_decl = re.search(r'(?m)^\s*(const|let|var)\s+BASE\s*=', s) is not None
if uses_base and not has_base_decl:
    inject = '  const BASE = (window.VSP_UI_BASE || window.__VSP_UI_BASE || location.origin);\n'
    # Prefer inject right before "const api = {"
    s2, n = re.subn(r'(?m)^(\s*)(const|let|var)\s+api\s*=\s*\{', r'\1' + inject + r'\1\2 api = {', s, count=1)
    if n == 0:
        # fallback: inject after "use strict" if exists, else after first line
        if re.search(r'(?m)^\s*["\']use strict["\']\s*;\s*$', s):
            s2, n2 = re.subn(r'(?m)^(\s*["\']use strict["\']\s*;\s*)$', r'\1\n' + inject.rstrip("\n"), s, count=1)
            if n2:
                s = s2; changed += 1
        else:
            lines = s.splitlines(True)
            if lines:
                lines.insert(1, inject)
                s = "".join(lines); changed += 1

p.write_text(s, encoding="utf-8")
print("[OK] JS patched, changes=", changed)
PY

echo "== [2] JS syntax check =="
node --check "$JS" >/dev/null
echo "[OK] node --check passed"

echo "== [3] Patch backend compat endpoints (run_file + rule_overrides_v1) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# find handler for /api/vsp/rule_overrides (to delegate)
rule_handler = None
m = re.search(r'@app\.(?:route|get|post)\(\s*[\'"]/api/vsp/rule_overrides[\'"]\s*(?:,|\))', s)
if m:
    tail = s[m.end():]
    m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(', tail)
    if m2:
        rule_handler = m2.group(1)

need_insert = []
if "/api/vsp/run_file" not in s:
    need_insert.append("run_file")
if "/api/vsp/rule_overrides_v1" not in s:
    need_insert.append("rule_overrides_v1")

if not need_insert:
    print("[OK] backend already has compat endpoints; no change")
else:
    block = []

    # Ensure imports for redirect/request
    # (Most likely already present; we won't fight it if duplicated.)
    # Insert compat block before if __name__ == '__main__' if possible, else append.
    block.append("\n# ==== VSP Commercial compat endpoints (auto) ====\n")

    if "run_file" in need_insert:
        block.append(textwrap.dedent("""
        @app.get("/api/vsp/run_file")
        def api_vsp_run_file_compat():
            # Legacy UI calls /api/vsp/run_file?rid=...&name=...
            # New contract: /api/vsp/run_file_allow?rid=...&path=...
            rid = (request.args.get("rid") or "").strip()
            name = (request.args.get("name") or request.args.get("path") or "").strip()
            if name.endswith("/") or name in ("reports", "reports/", "report", "report/"):
                # best-effort: show a useful JSON instead of a folder
                name = "reports/run_gate_summary.json"
            # Redirect keeps behavior simple; fetch() follows redirect by default.
            from urllib.parse import quote
            return redirect(f"/api/vsp/run_file_allow?rid={quote(rid)}&path={quote(name)}", code=302)
        """).strip("\n") + "\n\n")

    if "rule_overrides_v1" in need_insert:
        if rule_handler:
            block.append(textwrap.dedent(f"""
            @app.route("/api/vsp/rule_overrides_v1", methods=["GET","POST"])
            def api_vsp_rule_overrides_v1_compat():
                # Delegate to the working endpoint handler: /api/vsp/rule_overrides
                return {rule_handler}()
            """).strip("\n") + "\n")
        else:
            # Fallback: redirect GET only
            block.append(textwrap.dedent("""
            @app.get("/api/vsp/rule_overrides_v1")
            def api_vsp_rule_overrides_v1_compat():
                return redirect("/api/vsp/rule_overrides", code=302)
            """).strip("\n") + "\n")

    insert = "\n".join(block)

    main_guard = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
    if main_guard:
        s = s[:main_guard.start()] + insert + "\n" + s[main_guard.start():]
    else:
        s = s + "\n" + insert

    p.write_text(s, encoding="utf-8")
    print("[OK] backend compat inserted:", ", ".join(need_insert))
PY

echo "== [4] python compile check =="
python3 -m py_compile "$APP"
echo "[OK] py_compile passed"

echo "== [5] restart service (best-effort) =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl not found; restart manually if needed"
fi

echo "[DONE] Now hard-refresh browser: Ctrl+Shift+R (or clear cache for this site)."
