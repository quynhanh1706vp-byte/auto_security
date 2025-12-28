#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
TS="$(date +%Y%m%d_%H%M%S)"

A="static/js/vsp_tabs4_autorid_v1.js"
C="static/js/vsp_tabs3_common_v3.js"
R="static/js/vsp_runs_reports_overlay_v1.js"

for f in "$A" "$C" "$R"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
done

cp -f "$A" "${A}.bak_evt_${TS}"
cp -f "$C" "${C}.bak_evt_${TS}"
cp -f "$R" "${R}.bak_evt_${TS}"
echo "[BACKUP] $A.bak_evt_${TS}"
echo "[BACKUP] $C.bak_evt_${TS}"
echo "[BACKUP] $R.bak_evt_${TS}"

# 1) Harden autorid: always dispatch VSP_RID_CHANGED
node - <<'NODE'
const fs = require("fs");

const A="static/js/vsp_tabs4_autorid_v1.js";
let s=fs.readFileSync(A,"utf8");

const MARK="VSP_P1_TABS4_AUTORID_DISPATCH_EVT_V1";
if(!s.includes(MARK)){
  s += `\n\n/* ${MARK} */\n(()=>{\n  try{\n    const KEY='VSP_RID_CURRENT';\n    const emit=(rid,prev)=>{\n      try{ window.dispatchEvent(new CustomEvent('VSP_RID_CHANGED',{detail:{rid,prev,ts:Date.now()}})); }catch(e){}\n    };\n    // best-effort wrap setRid if exists\n    const w=window;\n    const oldSet = w.VSP_setRid || null;\n    if(typeof oldSet==='function'){\n      w.VSP_setRid = function(rid){\n        const prev = (localStorage.getItem(KEY)||'');\n        const out = oldSet.apply(this, arguments);\n        try{ localStorage.setItem(KEY, String(rid||'')); }catch(e){}\n        if(String(rid||'') && String(rid||'')!==String(prev||'')) emit(String(rid||''), String(prev||''));\n        return out;\n      };\n    }\n    // also emit once on load if rid exists\n    const cur = (localStorage.getItem(KEY)||'');\n    if(cur) emit(cur,'');\n  }catch(e){}\n})();\n`;
  fs.writeFileSync(A,s);
  console.log("[OK] patched autorid dispatch event");
}else{
  console.log("[OK] autorid event already present");
}
NODE

# 2) Add listeners (safe: only call if functions exist)
node - <<'NODE'
const fs = require("fs");
function patch(file, mark, code){
  let s=fs.readFileSync(file,"utf8");
  if(s.includes(mark)){ console.log("[OK] already:", file, mark); return; }
  s += "\n\n/* "+mark+" */\n"+code+"\n";
  fs.writeFileSync(file,s);
  console.log("[OK] patched:", file, mark);
}

patch("static/js/vsp_tabs3_common_v3.js",
  "VSP_P1_TABS3_LISTEN_RID_CHANGED_V1",
  `(()=>{\n  try{\n    window.addEventListener('VSP_RID_CHANGED',(ev)=>{\n      try{\n        // call reload hooks if present\n        if(typeof window.VSP_reloadDataSource==='function') window.VSP_reloadDataSource(ev.detail||{});\n        if(typeof window.VSP_reloadRuleOverrides==='function') window.VSP_reloadRuleOverrides(ev.detail||{});\n        if(typeof window.VSP_reloadSettings==='function') window.VSP_reloadSettings(ev.detail||{});\n      }catch(e){}\n    });\n  }catch(e){}\n})();`
);

patch("static/js/vsp_runs_reports_overlay_v1.js",
  "VSP_P1_RUNS_LISTEN_RID_CHANGED_V1",
  `(()=>{\n  try{\n    window.addEventListener('VSP_RID_CHANGED',(ev)=>{\n      try{\n        if(typeof window.VSP_reloadRuns==='function') window.VSP_reloadRuns(ev.detail||{});\n      }catch(e){}\n    });\n  }catch(e){}\n})();`
);
NODE

node --check static/js/vsp_tabs4_autorid_v1.js
node --check static/js/vsp_tabs3_common_v3.js
node --check static/js/vsp_runs_reports_overlay_v1.js
echo "[OK] node --check passed"
