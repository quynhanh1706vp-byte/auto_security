#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sed; need date; need curl

PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF (run in /home/test/Data/SECURITY_BUNDLE/ui)"; exit 2; }

TPL="$(python3 - <<'PY'
import ast
from pathlib import Path

src = Path("vsp_demo_app.py").read_text(encoding="utf-8", errors="replace")
tree = ast.parse(src)

def is_route_deco(dec):
    # matches: @app.route('/vsp5') or @app.get('/vsp5')
    if not isinstance(dec, ast.Call): return False
    if not isinstance(dec.func, ast.Attribute): return False
    if dec.func.attr not in ("route","get"): return False
    if not dec.args: return False
    a0 = dec.args[0]
    if isinstance(a0, ast.Constant) and isinstance(a0.value, str):
        return a0.value == "/vsp5"
    return False

def find_render_template_str(fn):
    # find first render_template("xxx.html") string constant in function body
    for node in ast.walk(fn):
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name) and node.func.id == "render_template":
                if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
                    v=node.args[0].value
                    if v.endswith(".html"):
                        return v
    return None

tpl=None
for node in tree.body:
    if isinstance(node, ast.FunctionDef):
        if any(is_route_deco(d) for d in node.decorator_list):
            tpl = find_render_template_str(node)
            break

print(tpl or "")
PY
)"

[ -n "$TPL" ] || { echo "[ERR] cannot detect template used by /vsp5 in vsp_demo_app.py"; exit 3; }

TP="templates/$TPL"
[ -f "$TP" ] || { echo "[ERR] template not found: $TP"; exit 4; }

echo "[ROUTE_PY]=$PYF"
echo "[TPL]=$TP"

JS="/static/js/vsp_runs_tab_resolved_v1.js"
[ -f "static/js/vsp_runs_tab_resolved_v1.js" ] || { echo "[ERR] missing static/js/vsp_runs_tab_resolved_v1.js"; exit 5; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TP" "${TP}.bak_include_runs_enh_${TS}"
echo "[BACKUP] ${TP}.bak_include_runs_enh_${TS}"

MARK="VSP5_INCLUDE_RUNS_ENHANCER_P0_V3"
if grep -q "$MARK" "$TP"; then
  echo "[OK] marker already present"
else
  sed -i "s#</body>#\n<!-- ${MARK} -->\n<script defer src=\"${JS}?v=${TS}\"></script>\n</body>#I" "$TP"
  echo "[OK] injected script into $TP"
fi

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== verify /vsp5 includes runs js =="
HTML="$(curl -sS http://127.0.0.1:8910/vsp5 || true)"
echo "$HTML" | grep -q "vsp_runs_tab_resolved_v1.js" && echo "[OK] script present in /vsp5 HTML" || {
  echo "[FAIL] /vsp5 HTML does NOT include vsp_runs_tab_resolved_v1.js"
  echo "Loaded JS list:"
  echo "$HTML" | grep -oE '/static/js/[^"]+' | sort -u | sed -n '1,200p'
  exit 6
}

echo "Loaded JS list:"
echo "$HTML" | grep -oE '/static/js/[^"]+' | sort -u | sed -n '1,200p'
