#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_global_hyd_${TS}" && echo "[BACKUP] $F.bak_global_hyd_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_GLOBAL_KPI_HYDRATOR_FROM_EXTRAS_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r'''
/* === VSP_GLOBAL_KPI_HYDRATOR_FROM_EXTRAS_P1_V1 ===
   Purpose: hydrate KPI cards from /api/vsp/dashboard_v3_extras_v1 regardless of internal module function names.
   Requires: global _vspSetTextK/_vspSetHTMLK/_vspKpiLock from VSP_GLOBAL_KPI_GUARDS_P1_V2.
*/
(function(){
  function _normRid(x){
    try{
      x = String(x||"").trim();
      x = x.replace(/^RUN[_\-\s]+/i,"").replace(/^RID[:\s]+/i,"");
      const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return m[1].toUpperCase();
      return x.replace(/\s+/g,"_");
    }catch(_){ return ""; }
  }
  function _getRid(){
    // 1) shared rid state
    try{
      const st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE || window.__vsp_rid_state;
      if(st){
        if(st.rid || st.run_id) return _normRid(st.rid || st.run_id);
        if(st.state && (st.state.rid || st.state.run_id)) return _normRid(st.state.rid || st.state.run_id);
        if(typeof st.get === "function"){
          const v = st.get();
          if(v && (v.rid || v.run_id)) return _normRid(v.rid || v.run_id);
        }
      }
    }catch(_){}
    // 2) scan page text
    try{
      const txt = (document && document.body && document.body.innerText) ? document.body.innerText : "";
      const m = txt.match(/(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return _normRid(m[1]);
    }catch(_){}
    return "";
  }
  function _hasKpiDom(){
    try{ return !!(document.getElementById("kpi-overall") && document.getElementById("kpi-gate")); }
    catch(_){ return false; }
  }
  function _fmtBySev(bySev){
    try{
      if(!bySev) return "";
      const order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const out=[];
      for(const k of order){
        if(bySev[k]!==undefined) out.push(k[0]+":"+bySev[k]);
      }
      return out.join(" ");
    }catch(_){ return ""; }
  }
  async function _fetchExtras(rid){
    if(!rid) return null;
    const u="/api/vsp/dashboard_v3_extras_v1?rid="+encodeURIComponent(rid);
    try{
      const r=await fetch(u,{cache:"no-store"});
      if(!r.ok) return null;
      const j=await r.json();
      return (j && j.ok && j.kpi) ? j : null;
    }catch(_){ return null; }
  }
  function _apply(j){
    try{
      if(!j || !j.kpi) return false;
      const k=j.kpi||{};
      const total = (k.total ?? 0);
      const eff   = (k.effective ?? 0);
      const degr  = (k.degraded ?? 0);
      const unk   = (k.unknown_count ?? 0);
      const score = (k.score===undefined || k.score===null) ? "" : k.score;

      const verdict = (degr>0) ? "DEGRADED" : (total>0 ? "OK" : "EMPTY");
      const gateTxt = (score!=="") ? (String(score)+"/100") : verdict;

      // set + lock so status_v2 won't overwrite
      _vspSetTextK("kpi-overall", verdict);
      _vspSetTextK("kpi-overall-sub", `total ${total} | eff ${eff} | degr ${degr} | unk ${unk}`);
      _vspKpiLock("kpi-overall"); _vspKpiLock("kpi-overall-sub");

      _vspSetTextK("kpi-gate", gateTxt);
      // by_sev may not exist; keep safe
      const bySev = k.by_sev || k.bySev || null;
      _vspSetTextK("kpi-gate-sub", bySev ? _fmtBySev(bySev) : "");
      _vspKpiLock("kpi-gate"); _vspKpiLock("kpi-gate-sub");

      return true;
    }catch(_){ return false; }
  }

  async function _run(){
    try{
      if(!_hasKpiDom()) return;
      const rid=_getRid();
      if(!rid) return;
      const j=await _fetchExtras(rid);
      if(!j) return;
      _apply(j);
    }catch(_){}
  }

  function _install(){
    try{
      if(window.__VSP_GLOBAL_KPI_HYDRATOR_INSTALLED__) return;
      window.__VSP_GLOBAL_KPI_HYDRATOR_INSTALLED__ = 1;

      // immediate + retry
      _run(); setTimeout(_run,200); setTimeout(_run,800); setTimeout(_run,1600);

      // observe pane mount / route change
      const obs = new MutationObserver(()=>{ if(_hasKpiDom()) _run(); });
      obs.observe(document.documentElement || document.body, {subtree:true, childList:true});

      // periodic safety
      setInterval(_run, 3000);
    }catch(_){}
  }

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", _install);
  }else{
    _install();
  }
})();
'''

# prepend after the global guards block if exists, else prepend at top
if "VSP_GLOBAL_KPI_GUARDS_P1_V2" in s:
    # insert right after END marker block for readability
    idx = s.find("/* === END VSP_GLOBAL_KPI_GUARDS_P1_V2 === */")
    if idx != -1:
        idx2 = idx + len("/* === END VSP_GLOBAL_KPI_GUARDS_P1_V2 === */")
        s = s[:idx2] + "\n" + ins + "\n" + s[idx2:]
    else:
        s = ins + "\n" + s
else:
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
