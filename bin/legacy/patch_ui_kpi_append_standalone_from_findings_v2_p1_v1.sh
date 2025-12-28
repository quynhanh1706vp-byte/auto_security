#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_standalone_${TS}" && echo "[BACKUP] $F.bak_kpi_standalone_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_KPI_STANDALONE_FROM_FINDINGS_V2_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

addon = r'''
/* === VSP_KPI_STANDALONE_FROM_FINDINGS_V2_P1_V1 ===
   Standalone hydrator that DOES NOT rely on DOMContentLoaded timing or internal module scope.
   Source of truth: /api/vsp/findings_unified_v2/<rid>?limit=1  (counts + total)
*/
(function(){
  if (window.__VSP_KPI_STANDALONE_V2_P1__) return;
  window.__VSP_KPI_STANDALONE_V2_P1__ = 1;

  function normRid(x){
    try{
      x = String(x||"").trim();
      x = x.replace(/^RUN[_\-\s]+/i,"").replace(/^RID[:\s]+/i,"");
      var m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
      return (m && m[1]) ? m[1] : x.replace(/\s+/g,"_");
    }catch(_){ return ""; }
  }

  function ridFromState(){
    try{
      var st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE || window.__vsp_rid_state;
      if(!st) return "";
      if (st.rid || st.run_id) return normRid(st.rid || st.run_id);
      if (st.state && (st.state.rid || st.state.run_id)) return normRid(st.state.rid || st.state.run_id);
      if (typeof st.get === "function"){
        var v = st.get();
        if (v && (v.rid || v.run_id)) return normRid(v.rid || v.run_id);
      }
    }catch(_){}
    return "";
  }

  async function fetchLatestRid(){
    try{
      var u="/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1";
      var r=await fetch(u,{cache:"no-store"});
      if(!r.ok) return "";
      var j=await r.json();
      var it=(j && j.items && j.items[0]) ? j.items[0] : null;
      return normRid(it ? (it.run_id || it.rid || "") : "");
    }catch(_){ return ""; }
  }

  async function fetchFindingsCounts(rid){
    try{
      if(!rid) return null;
      var u="/api/vsp/findings_unified_v2/"+encodeURIComponent(rid)+"?limit=1";
      var r=await fetch(u,{cache:"no-store"});
      if(!r.ok) return null;
      var j=await r.json();
      if(!j || !j.ok) return null;
      return j;
    }catch(_){ return null; }
  }

  function fmtBySev(bySev){
    if(!bySev) return "";
    var order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    var out=[];
    for (var i=0;i<order.length;i++){
      var k=order[i];
      if (bySev[k] !== undefined) out.push(k[0]+":"+bySev[k]);
    }
    return out.join(" ");
  }

  function pickTool(byTool, want){
    if(!byTool) return null;
    if (byTool[want] !== undefined) return byTool[want];
    var keys=Object.keys(byTool);
    for (var i=0;i<keys.length;i++){
      if (String(keys[i]||"").toUpperCase() === String(want||"").toUpperCase()) return byTool[keys[i]];
    }
    return null;
  }

  function setText(id, v){
    try{
      if (typeof window._vspSetTextK === "function") return window._vspSetTextK(id, v);
    }catch(_){}
    // fallback
    try{
      var el=document.getElementById(id);
      if(!el) return false;
      el.textContent = (v===0) ? "0" : (v ? String(v) : "—");
      return true;
    }catch(_){ return false; }
  }

  function applyFromUnified(j){
    if(!j) return false;
    var total = (j.total !== undefined && j.total !== null) ? j.total : 0;
    var c = j.counts || {};
    var bySev = c.by_sev || {};
    var byTool = c.by_tool || {};
    var unk = (c.unknown_count !== undefined && c.unknown_count !== null) ? c.unknown_count : 0;
    var eff = Math.max(0, total - unk);
    var degr = Math.max(0, unk);

    var score = (total>0) ? Math.round((eff/Math.max(1,total))*100) : 0;
    var verdict = (degr>0) ? "DEGRADED" : (total>0 ? "OK" : "EMPTY");
    var gateTxt = String(score) + "/100";

    var gtl = pickTool(byTool,"GITLEAKS");
    var cql = pickTool(byTool,"CODEQL");

    var ok=0;
    ok += setText("kpi-overall", verdict) ? 1:0;
    ok += setText("kpi-overall-sub", "total "+total+" | eff "+eff+" | degr "+degr+" | unk "+unk) ? 1:0;
    ok += setText("kpi-gate", gateTxt) ? 1:0;
    ok += setText("kpi-gate-sub", fmtBySev(bySev)) ? 1:0;

    ok += setText("kpi-gitleaks", (gtl===null) ? "NOT_RUN" : gtl) ? 1:0;
    ok += setText("kpi-gitleaks-sub", "GITLEAKS") ? 1:0;
    ok += setText("kpi-codeql", (cql===null) ? "NOT_RUN" : cql) ? 1:0;
    ok += setText("kpi-codeql-sub", "CODEQL") ? 1:0;

    return ok>=2;
  }

  async function tick(){
    try{
      var rid = ridFromState();
      if(!rid) rid = await fetchLatestRid();
      if(!rid) return;

      var j = await fetchFindingsCounts(rid);
      if(!j) return;

      applyFromUnified(j);
    }catch(_){}
  }

  // Start immediately (works even if script loads after DOMContentLoaded)
  try{ tick(); }catch(_){}
  try{ setTimeout(tick, 250); }catch(_){}
  try{ setTimeout(tick, 800); }catch(_){}
  try{ setInterval(tick, 2000); }catch(_){}
})();
'''

s = s + "\n\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
