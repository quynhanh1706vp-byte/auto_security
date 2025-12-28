#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] snapshot backups =="
for f in vsp_demo_app.py static/js/vsp_dashboard_luxe_v1.js static/js/vsp_bundle_tabs5_v1.js static/js/vsp_dashboard_gate_story_v1.js; do
  [ -f "$f" ] || continue
  cp -f "$f" "$f.bak_p2fix_${TS}"
  echo "[BACKUP] $f.bak_p2fix_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re, subprocess, os, time

ROOT = Path(".")
TEMPL = ROOT/"templates"

def has_node():
    from shutil import which
    return which("node") is not None

def node_check(p: Path) -> bool:
    if not has_node():
        return False
    try:
        subprocess.check_call(["node","--check",str(p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception:
        return False

# ------------------------------------------------------------
# 1) Patch loader: HEAD -> GET to avoid HEAD being blocked/failing
# ------------------------------------------------------------
def patch_head_to_get(p: Path) -> bool:
    if not p.exists(): return False
    s = p.read_text(errors="ignore")
    s2 = s
    # common patterns
    s2 = s2.replace('method:"HEAD"', 'method:"GET"')
    s2 = s2.replace("method:'HEAD'", "method:'GET'")
    s2 = s2.replace('method: "HEAD"', 'method: "GET"')
    s2 = s2.replace("method: 'HEAD'", "method: 'GET'")
    if s2 != s:
        p.write_text(s2)
        return True
    return False

changed = []
for js in ["static/js/vsp_dashboard_luxe_v1.js", "static/js/vsp_bundle_tabs5_v1.js", "static/js/vsp_dash_only_v1.js"]:
    if patch_head_to_get(ROOT/js):
        changed.append(js)

# ------------------------------------------------------------
# 2) Ensure optional JS files exist (create harmless stubs if missing)
# ------------------------------------------------------------
stubs = {
 "static/js/vsp_dash_only_v1.js": r"""/* VSP_STUB_DASH_ONLY_V1 */
(function(){
  try{
    window.VSP_DASH_ONLY = window.VSP_DASH_ONLY || {};
    window.VSP_DASH_ONLY.loaded_at = Date.now();
    console.log("[VSP][STUB] vsp_dash_only_v1.js loaded");
  }catch(e){}
})();
""",
 "static/js/vsp_dashboard_kpi_force_any_v1.js": r"""/* VSP_STUB_KPI_FORCE_ANY_V1 */
(function(){
  try{
    window.VSP_KPI_FORCE_ANY = window.VSP_KPI_FORCE_ANY || {};
    window.VSP_KPI_FORCE_ANY.loaded_at = Date.now();
    console.log("[VSP][STUB] vsp_dashboard_kpi_force_any_v1.js loaded");
  }catch(e){}
})();
""",
 "static/js/vsp_dashboard_charts_pretty_v3.js": r"""/* VSP_STUB_CHARTS_PRETTY_V3 */
(function(){
  try{
    window.VSP_CHARTS_PRETTY = window.VSP_CHARTS_PRETTY || {};
    window.VSP_CHARTS_PRETTY.loaded_at = Date.now();
    console.log("[VSP][STUB] vsp_dashboard_charts_pretty_v3.js loaded");
  }catch(e){}
})();
""",
}

for rel, body in stubs.items():
    p = ROOT/rel
    if not p.exists():
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
        changed.append(rel + " (stub-created)")

# ------------------------------------------------------------
# 3) Fix gate_story syntax error:
#    - if current file fails node --check => rollback to newest backup that passes
#    - if none passes => write fallback no-op to avoid crashing UI
# ------------------------------------------------------------
gate = ROOT/"static/js/vsp_dashboard_gate_story_v1.js"
if gate.exists() and has_node() and (not node_check(gate)):
    backups = sorted(gate.parent.glob(gate.name + ".bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
    good = None
    for b in backups:
        if node_check(b):
            good = b
            break
    if good:
        gate.write_text(good.read_text(errors="ignore"))
        changed.append(f"static/js/vsp_dashboard_gate_story_v1.js (rollback <- {good.name})")

# If still broken or node not available and file contains obvious bad token at column start
if gate.exists():
    bad = False
    s = gate.read_text(errors="ignore")
    if has_node():
        bad = not node_check(gate)
    else:
        # heuristic: line starts with "try" at top-level after a broken brace pattern
        bad = ("Unexpected token" in s) or ("\ntry\n" in s) or ("\ntry {" in s and "function" not in s[:200])

    if bad:
        gate.write_text(r"""/* VSP_FALLBACK_GATE_STORY_V1 (no-op, prevents crash) */
(function(){
  try{
    window.VSP_GATE_STORY = window.VSP_GATE_STORY || {};
    window.VSP_GATE_STORY.init = window.VSP_GATE_STORY.init || function(){ console.log("[VSP][FALLBACK] gate_story init"); };
    console.log("[VSP][FALLBACK] vsp_dashboard_gate_story_v1.js loaded (fallback)");
  }catch(e){}
})();
""")
        changed.append("static/js/vsp_dashboard_gate_story_v1.js (fallback-written)")

# ------------------------------------------------------------
# 4) Ensure /vsp5 template has anchor #vsp-dashboard-main
#    Find template used by route '/vsp5' from vsp_demo_app.py render_template(...)
# ------------------------------------------------------------
tpls = set()
app_py = ROOT/"vsp_demo_app.py"
if app_py.exists():
    app = app_py.read_text(errors="ignore")
    # find @app.route('/vsp5') ... render_template('X.html')
    m = re.search(r"@app\.route\(\s*['\"]\/vsp5['\"][\s\S]{0,1200}?render_template\(\s*['\"]([^'\"]+)['\"]", app)
    if m:
        tpls.add(m.group(1))

# fallback: pick templates that contain vsp_bundle_tabs5_v1.js and look like dashboard
if not tpls and TEMPL.exists():
    for p in TEMPL.glob("*.html"):
        txt = p.read_text(errors="ignore")
        if ("vsp_bundle_tabs5_v1.js" in txt) and ("/vsp5" in txt or "vsp5" in p.name.lower()):
            tpls.add(p.name)

def ensure_anchor(html: str) -> str:
    if 'id="vsp-dashboard-main"' in html:
        return html
    # insert right after <body ...>
    out = re.sub(r"(<body[^>]*>)", r'\1\n  <div id="vsp-dashboard-main"></div>', html, count=1, flags=re.I)
    if out != html:
        return out
    # fallback: before </body>
    out = re.sub(r"(</body>)", r'  <div id="vsp-dashboard-main"></div>\n\1', html, count=1, flags=re.I)
    return out

patched_tpl = 0
for name in tpls:
    p = TEMPL/name
    if p.exists():
        s = p.read_text(errors="ignore")
        s2 = ensure_anchor(s)
        if s2 != s:
            p.write_text(s2)
            patched_tpl += 1
            changed.append(f"templates/{name} (anchor-added)")

print("[OK] changed items:", len(changed))
for x in changed[:200]:
    print(" -", x)
PY

echo "== [1] restart service (if exists) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== [2] quick verify =="
echo "-- anchor --"
curl -sS "$BASE/vsp5" | grep -n 'id="vsp-dashboard-main"' | head -n 2 || echo "[WARN] anchor still missing"

echo "-- static js status --"
for f in vsp_dash_only_v1.js vsp_dashboard_kpi_force_any_v1.js vsp_dashboard_gate_story_v1.js vsp_dashboard_charts_pretty_v3.js; do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE/static/js/$f?v=$(date +%s)" || true)"
  echo "$f => HTTP $code"
done

echo "[DONE] If browser still shows old errors: hard refresh (Ctrl+Shift+R)."
