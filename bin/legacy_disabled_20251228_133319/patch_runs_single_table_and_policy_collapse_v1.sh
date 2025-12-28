#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_commercial_layout_controller_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_runs_single_${TS}" && echo "[BACKUP] $F.bak_runs_single_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_commercial_layout_controller_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RUNS_SINGLE_TABLE_V1" in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = r"""
  // VSP_RUNS_SINGLE_TABLE_V1: de-duplicate runs views + collapse policy/verdict
  function __vsp_hide_if_match(sel_list){
    for (const sel of sel_list){
      try{
        document.querySelectorAll(sel).forEach(el=>{
          // only hide big legacy blocks, don't hide the main runs mount
          if(!el) return;
          if(el.id === 'vsp-runs-main') return;
          el.style.display = 'none';
          el.setAttribute('data-vsp-hidden', 'runs-dedup');
        });
      }catch(_){}
    }
  }

  function __vsp_policy_panel_el(){
    return document.getElementById('vsp-policy-verdict-panel')
        || document.getElementById('vsp_policy_panel_v1')
        || document.getElementById('vsp_policy_panel')
        || document.querySelector('[data-vsp-policy-verdict-panel]');
  }

  function __vsp_collapse_policy_default(){
    const p = __vsp_policy_panel_el();
    if(!p) return;
    if(p.dataset.vspCollapsedInit) return;
    p.dataset.vspCollapsedInit = '1';
    p.style.display = 'none';
  }

  function __vsp_ensure_policy_toggle(){
    let btn = document.getElementById('vsp-policy-verdict-toggle');
    if(btn) return;
    btn = document.createElement('button');
    btn.id='vsp-policy-verdict-toggle';
    btn.type='button';
    btn.textContent='Policy / Verdict';
    btn.style.cssText = [
      'position:fixed','left:14px','bottom:14px','z-index:9999',
      'padding:8px 10px','border-radius:10px',
      'border:1px solid rgba(255,255,255,.12)',
      'background:rgba(17,20,28,.92)','color:#e7eaf0',
      'font-size:12px','cursor:pointer',
      'box-shadow:0 8px 22px rgba(0,0,0,.35)'
    ].join(';') + ';';
    btn.addEventListener('click', function(){
      const p = __vsp_policy_panel_el();
      if(!p) return;
      p.style.display = (p.style.display === 'none') ? '' : 'none';
    });
    document.body.appendChild(btn);
  }
"""

# insert helpers near apply() function (after it exists)
# safest: append at end of file before final "})();" if present
idx = s.rfind("})();")
if idx != -1:
    s = s[:idx] + inject + "\n" + s[idx:]
else:
    s = s + "\n" + inject

# now patch apply(): if route is runs, hide legacy duplicated blocks + collapse policy
# We'll add calls inside existing apply() by string injection
if "function apply()" in s:
    s = s.replace(
        "function apply(){",
        "function apply(){\n    // VSP_RUNS_SINGLE_TABLE_V1 hook\n"
    )
    # after routeName & isRuns computed usually; just add safe calls at end of apply
    s = s.replace(
        "try { console.log('[VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE] apply route=', r, 'isRuns=', isRuns); } catch(_){ }",
        "if(isRuns){\n"
        "      __vsp_hide_if_match([\n"
        "        // legacy duplicated runs/report sections\n"
        "        '#runs-strip', '.runs-strip', '.runs-strip-wrap',\n"
        "        '.vsp-runs-strip', '.vsp-runs-strip-wrap',\n"
        "        // legacy runs & reports big table blocks\n"
        "        '.runs-and-reports', '.vsp-runs-and-reports',\n"
        "        'section#runs_reports', 'div#runs_reports',\n"
        "        // any card titled RUNS & REPORTS (best-effort)\n"
        "        '.vsp-card:has(h2), .vsp-card:has(h3)'\n"
        "      ]);\n"
        "      __vsp_collapse_policy_default();\n"
        "      __vsp_ensure_policy_toggle();\n"
        "    }\n"
        "    try { console.log('[VSP_COMMERCIAL_LAYOUT_CONTROLLER_V3_SAFE] apply route=', r, 'isRuns=', isRuns); } catch(_){ }"
    )

p.write_text(s, encoding="utf-8")
print("[OK] injected runs single-table + policy collapse into controller")
PY

node --check "$F" >/dev/null && echo "[OK] node --check controller" || { echo "[ERR] controller syntax failed"; exit 3; }

echo "[DONE] Restart UI + Ctrl+Shift+R + Ctrl+0"
