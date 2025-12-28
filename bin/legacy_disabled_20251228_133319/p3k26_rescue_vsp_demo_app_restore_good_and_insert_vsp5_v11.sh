#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

echo "== [0] backup current broken app =="
cp -f "$APP" "${APP}.bak_p3k26_v11_before_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v11_before_${TS}"

echo "== [1] find a backup that py_compile passes =="
GOOD=""
for f in $(ls -1t ${APP}.bak_* 2>/dev/null || true); do
  cp -f "$f" "$APP"
  if python3 -m py_compile "$APP" >/dev/null 2>&1; then
    GOOD="$f"
    echo "[OK] found good backup: $GOOD"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] no backup compiles. Showing current error context:"
  python3 -m py_compile "$APP" || true
  echo "== tail 80 of file =="
  tail -n 80 "$APP" || true
  exit 2
fi

echo "== [2] patch: insert /vsp5 HTML route at safe location (AST after app=Flask) =="
python3 - <<'PY'
from pathlib import Path
import ast, re

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

TAG = "P3K26_VSP5_HTML_ROUTE_V11"
# Remove any previously injected broken blocks (v8/v9/v10)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V8.*?(?=^\s*@app\.route|\Z)', '', s)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V9.*?(?=^\s*@app\.route|\Z)', '', s)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V10.*?(?=^\s*@app\.route|\Z)', '', s)

if TAG in s:
    print("[OK] already patched (no-op)")
    APP.write_text(s, encoding="utf-8")
    raise SystemExit(0)

route_block = (
f"\n# {TAG}: /vsp5 must return HTML shell (never JSON)\n"
"@app.route('/vsp5')\n"
"def vsp5():\n"
"    from flask import Response, render_template\n"
"    import os\n"
"    try:\n"
"        for cand in (\n"
"            'vsp_dashboard_2025.html',\n"
"            'vsp_dashboard_luxe.html',\n"
"            'vsp_dashboard_2025_luxe.html',\n"
"            'vsp5.html',\n"
"        ):\n"
"            tdir = getattr(app, 'template_folder', None) or 'templates'\n"
"            if os.path.isfile(os.path.join(tdir, cand)):\n"
"                return render_template(cand)\n"
"    except Exception:\n"
"        pass\n"
"    html = (\n"
"        '<!doctype html><html><head><meta charset=\"utf-8\">'\n"
"        '<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">'\n"
"        '<title>VSP Dashboard</title>'\n"
"        '</head><body style=\"margin:0;background:#0b1220;color:#e5e7eb;\">'\n"
"        '<div id=\"vsp-dashboard-main\"></div>'\n"
"        '<script src=\"/static/js/vsp_bundle_tabs5_v1.js\"></script>'\n"
"        '</body></html>'\n"
"    )\n"
"    return Response(html, mimetype='text/html')\n"
)

# Parse AST to find "app = Flask(...)" assignment and insert after its end_lineno
tree = ast.parse(s)
insert_after_lineno = None

class FindAppAssign(ast.NodeVisitor):
    def visit_Assign(self, node):
        nonlocal insert_after_lineno
        try:
            if any(isinstance(t, ast.Name) and t.id == "app" for t in node.targets):
                # value could be Flask(...) call
                if isinstance(node.value, ast.Call):
                    fn = node.value.func
                    fn_name = fn.id if isinstance(fn, ast.Name) else (fn.attr if isinstance(fn, ast.Attribute) else "")
                    if fn_name == "Flask":
                        insert_after_lineno = getattr(node, "end_lineno", node.lineno)
        except Exception:
            pass
        self.generic_visit(node)

FindAppAssign().visit(tree)

lines = s.splitlines(True)
if insert_after_lineno:
    idx = insert_after_lineno  # 1-based line no -> insert at this index in list
    # ensure we insert at top-level (no indentation)
    lines.insert(idx, route_block + "\n")
    s2 = "".join(lines)
    print(f"[OK] inserted /vsp5 route after app=Flask at line {insert_after_lineno}")
else:
    # fallback: insert before first @app.route
    m = re.search(r'(?m)^\s*@app\.route\(', s)
    if not m:
        s2 = s + "\n" + route_block + "\n"
        print("[WARN] no @app.route found; appended at end")
    else:
        pos = m.start()
        s2 = s[:pos] + route_block + "\n\n" + s[pos:]
        print("[OK] inserted /vsp5 route before first @app.route (fallback)")

APP.write_text(s2, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

echo "== [3] py_compile (must pass) =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [4] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [5] smoke /vsp5 (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,90p'
echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true

echo "[DONE] p3k26_rescue_vsp_demo_app_restore_good_and_insert_vsp5_v11"
