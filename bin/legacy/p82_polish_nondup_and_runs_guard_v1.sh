#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date

TS="$(date +%Y%m%d_%H%M%S)"
ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }

TABS="static/js/vsp_bundle_tabs5_v1.js"
RUNS_QA="static/js/vsp_runs_quick_actions_v1.js"
PIN1="static/js/vsp_pin_dataset_badge_v1.js"
PIN2="static/js/vsp_pin_dataset_badge_v2.js"
KPI="static/js/vsp_runs_kpi_compact_v3.js"

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_p82_${TS}"
  ok "backup $f => ${f}.bak_p82_${TS}"
}

backup "$TABS"
backup "$RUNS_QA"
backup "$PIN1"
backup "$PIN2"
backup "$KPI"

python3 - <<'PY'
from pathlib import Path
import re

def patch_tabs5_hide_dashboard():
    p=Path("static/js/vsp_bundle_tabs5_v1.js")
    if not p.exists(): return "skip tabs5 (missing)"
    s=p.read_text(encoding="utf-8", errors="replace")
    if "VSP_P82_HIDE_DASHBOARD_NON_DASH_V1" in s:
        return "tabs5 already patched"
    # inject a small CSS hider for non-dashboard pages
    inj = r"""
/* VSP_P82_HIDE_DASHBOARD_NON_DASH_V1 */
(function(){
  try{
    var pn=(location.pathname||"");
    var isDash = (pn==="/vsp5" || pn==="/c/dashboard" || pn==="/dashboard");
    if(isDash) return;
    var css = [
      "#vsp-dashboard-main{display:none!important;}",
      "#vsp-dashboard-kpis{display:none!important;}",
      "#vsp-dashboard{display:none!important;}",
      ".vsp-dashboard{display:none!important;}",
      ".vsp-dashboard-kpi{display:none!important;}",
      ".vsp-kpi-strip{display:none!important;}"
    ].join("\\n");
    var st=document.createElement("style");
    st.setAttribute("data-vsp","p82-hide-dash-non-dash");
    st.textContent=css;
    (document.head||document.documentElement).appendChild(st);
    // best-effort remove if present
    ["vsp-dashboard-main","vsp-dashboard-kpis","vsp-dashboard"].forEach(function(id){
      var el=document.getElementById(id);
      if(el) el.style.display="none";
    });
  }catch(e){}
})();
"""
    # append near end (safe)
    s = s.rstrip() + "\n" + inj + "\n"
    p.write_text(s, encoding="utf-8")
    return "tabs5 patched (hide dashboard on non-dashboard tabs)"

def guard_dom_ops(path: Path):
    if not path.exists(): return f"skip {path} (missing)"
    s=path.read_text(encoding="utf-8", errors="replace")
    if "VSP_P82_DOM_GUARD_V1" in s:
        return f"{path.name} already patched"
    # 1) Fix the common typo pattern if present (harmless if absent)
    s = s.replace('trace:"TRACE"', '"TRACE"')

    # 2) Guard simple appendChild / insertBefore forms to avoid null crashes
    #    Only guards when the receiver is a simple identifier.
    def guard_append(m):
        var=m.group(1); arg=m.group(2)
        if "&&" in m.group(0): return m.group(0)
        return f"{var} && {var}.appendChild({arg});"
    def guard_insert(m):
        var=m.group(1); a=m.group(2); b=m.group(3)
        if "&&" in m.group(0): return m.group(0)
        return f"{var} && {var}.insertBefore({a}, {b});"

    s = re.sub(r'(?m)^\s*([A-Za-z_$][\w$]*)\.appendChild\(([^;]+)\);\s*$', guard_append, s)
    s = re.sub(r'(?m)^\s*([A-Za-z_$][\w$]*)\.insertBefore\(([^,]+),\s*([^)]+)\);\s*$', guard_insert, s)

    # 3) Add a small marker + window error handler (does not hide real bugs, just prevents blank screen)
    marker = r"""
/* VSP_P82_DOM_GUARD_V1 */
(function(){
  try{
    if(window.__VSP_P82_ERR_GUARD) return;
    window.__VSP_P82_ERR_GUARD = 1;
    window.addEventListener("error", function(ev){
      try{ console.warn("[VSP][P82] runtime error guarded:", ev && (ev.message||ev.error||ev)); }catch(e){}
    });
    window.addEventListener("unhandledrejection", function(ev){
      try{ console.warn("[VSP][P82] rejection guarded:", ev && (ev.reason||ev)); }catch(e){}
    });
  }catch(e){}
})();
"""
    s = s.rstrip() + "\n" + marker + "\n"
    path.write_text(s, encoding="utf-8")
    return f"{path.name} patched (guard appendChild/insertBefore + marker)"

msgs=[]
msgs.append(patch_tabs5_hide_dashboard())

for fn in [
    "static/js/vsp_runs_quick_actions_v1.js",
    "static/js/vsp_pin_dataset_badge_v1.js",
    "static/js/vsp_pin_dataset_badge_v2.js",
    "static/js/vsp_runs_kpi_compact_v3.js",
]:
    msgs.append(guard_dom_ops(Path(fn)))

print("\n".join("[OK] "+m for m in msgs))
PY

# syntax check (only for files that exist)
for f in "$TABS" "$RUNS_QA" "$PIN1" "$PIN2" "$KPI"; do
  if [ -f "$f" ]; then
    node -c "$f" >/dev/null && ok "syntax OK: $f" || { echo "[FAIL] syntax FAIL: $f" >&2; exit 2; }
  fi
done

echo "[DONE] P82 applied."
echo "[NEXT] Ctrl+Shift+R all tabs. Expect:"
echo " - /vsp5: dashboard OK"
echo " - /data_source /settings /rule_overrides: NO duplicated dashboard block"
echo " - /runs: not blank; console no fatal TypeError/SyntaxError"
