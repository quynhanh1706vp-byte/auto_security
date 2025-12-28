#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_data_source_tab_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p2v3hook_${TS}"
echo "[BACKUP] ${F}.bak_p2v3hook_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_data_source_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_DS_QUERY_FILTER_V3_HOOK" in s:
    print("[OK] already patched V3_HOOK")
    raise SystemExit(0)

# 1) extend state with sev/tool
s = re.sub(
    r'let\s+state\s*=\s*\{\s*rid:"",\s*limit:50,\s*offset:0,\s*q:""\s*\}\s*;',
    'let state = { rid:"", limit:50, offset:0, q:"", sev:"", tool:"" };',
    s, count=1
)

# 2) add severity select next to q input (v3 UI)
pat_qin = r'(const\s+qin\s*=\s*el\("input",\s*\{placeholder:"search in findings".*?\}\);)'
m = re.search(pat_qin, s, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot locate qin input block")

insert_ui = r'''
const sevSel = el("select", {style:{padding:"6px 8px", marginLeft:"8px", minWidth:"140px"}}, [
  el("option",{value:""},["All severities"]),
  el("option",{value:"CRITICAL"},["CRITICAL"]),
  el("option",{value:"HIGH"},["HIGH"]),
  el("option",{value:"MEDIUM"},["MEDIUM"]),
  el("option",{value:"LOW"},["LOW"]),
  el("option",{value:"INFO"},["INFO"]),
  el("option",{value:"TRACE"},["TRACE"]),
]);
sevSel.addEventListener("change", ()=>{ state.sev = (sevSel.value||""); state.offset=0; loadFindings(false); });
'''
s = s[:m.end(1)] + "\n" + insert_ui + s[m.end(1):]

# 3) ensure sevSel is attached to the toolbar (find where qin is appended)
# best-effort: after qin creation, there is usually a container append. We'll inject a safe attach near reload button line.
# If we can't find an obvious toolbar, we attach after qin is created by inserting "try append to parent" in init.
attach_marker = "VSP_P2_DS_QUERY_FILTER_V3_HOOK_ATTACH"
if attach_marker not in s:
    s = s.replace(
        'const btn = el("button", {style:{padding:"6px 10px",cursor:"pointer"}, onclick:()=>loadFindings(true)}, ["Reload"]);',
        'const btn = el("button", {style:{padding:"6px 10px",cursor:"pointer"}, onclick:()=>loadFindings(true)}, ["Reload"]);'
        '\n/* ===== VSP_P2_DS_QUERY_FILTER_V3_HOOK_ATTACH ===== */'
        '\ntry{ if(qin && qin.parentNode && !sevSel.parentNode) qin.parentNode.insertBefore(sevSel, btn||null); }catch(_){ }'
    )

# 4) filter inside renderRows(items) by state.sev/state.tool (client-side)
pat_render = r'function\s+renderRows\s*\(\s*items\s*\)\s*\{'
m2 = re.search(pat_render, s)
if not m2:
    raise SystemExit("[ERR] cannot locate renderRows()")
ins_filter = r'''
/* ===== VSP_P2_DS_QUERY_FILTER_V3_HOOK ===== */
try{
  if (items && items.length){
    const sevNeed = String(state.sev||"").toUpperCase().trim();
    const toolNeed = String(state.tool||"").toUpperCase().trim();
    if (sevNeed){
      items = items.filter(it => String(it.severity_norm||it.severity||it.level||"").toUpperCase() === sevNeed);
    }
    if (toolNeed){
      items = items.filter(it => String(it.tool||it.engine||"").toUpperCase().includes(toolNeed));
    }
  }
}catch(_){}
'''
s = s[:m2.end()] + "\n" + ins_filter + s[m2.end():]

# 5) parse query params and apply to state BEFORE first loadFindings()
# inject helper + call it before the initial loadFindings()
helper = r'''
function __vspDsApplyQueryFromUrl(){
  try{
    const sp = new URL(window.location.href).searchParams;
    const sev = String(sp.get("severity")||"").toUpperCase().trim();
    const q = String(sp.get("q")||"").trim();
    const tool = String(sp.get("tool")||"").trim();
    if (typeof q === "string"){ state.q = q; if (qin) qin.value = q; }
    if (sev){ state.sev = sev; try{ if (typeof sevSel !== "undefined") sevSel.value = sev; }catch(_){ } }
    if (tool){ state.tool = tool; }
    state.offset = 0;
  }catch(_){}
}
try{ window.__vspDsApplyQueryFromUrl = __vspDsApplyQueryFromUrl; }catch(_){}
'''
# place helper near qin change listener
anchor = 'qin.addEventListener("change", ()=>{ state.q = qin.value||""; state.offset=0; loadFindings(false); });'
if anchor not in s:
    raise SystemExit("[ERR] cannot locate qin change listener")
s = s.replace(anchor, anchor + "\n" + helper, 1)

# call before first loadFindings
s = s.replace('await loadRunsPick();\n    await loadFindings();',
              'await loadRunsPick();\n    try{ __vspDsApplyQueryFromUrl(); }catch(_){ }\n    await loadFindings();', 1)

p.write_text(s, encoding="utf-8")
print("[OK] patched: VSP_P2_DS_QUERY_FILTER_V3_HOOK")
PY

echo "[OK] done. Now HARD refresh browser (Ctrl+Shift+R) or open in Incognito:"
echo "  http://127.0.0.1:8910/data_source?severity=HIGH&q=codeql"
echo "  http://127.0.0.1:8910/data_source?severity=MEDIUM"
