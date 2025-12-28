#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

T="templates/vsp_4tabs_commercial_v1.html"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$T" "$T.bak_kpi_inline_${TS}" && echo "[BACKUP] $T.bak_kpi_inline_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

t=Path("templates/vsp_4tabs_commercial_v1.html")
s=t.read_text(encoding="utf-8", errors="ignore")

marker="VSP_TPL_KPI_INLINE_EXTRAS_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r"""
<!-- === VSP_TPL_KPI_INLINE_EXTRAS_P1_V1 === -->
<script>
(function(){
  function normRid(x){
    try{
      x = String(x||"").trim();
      x = x.replace(/^RUN[_\-\s]+/i,"").replace(/^RID[:\s]+/i,"");
      const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
      return (m && m[1]) ? m[1] : x.replace(/\s+/g,"_");
    }catch(_){ return ""; }
  }
  function getRid(){
    try{
      const st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE || window.__vsp_rid_state;
      if(st){
        if(st.rid || st.run_id) return normRid(st.rid || st.run_id);
        if(st.state && (st.state.rid || st.state.run_id)) return normRid(st.state.rid || st.state.run_id);
        if(typeof st.get === "function"){
          const v = st.get();
          if(v && (v.rid || v.run_id)) return normRid(v.rid || v.run_id);
        }
      }
    }catch(_){}
    try{
      const txt = document.body ? (document.body.innerText||"") : "";
      const m = txt.match(/RID:\s*(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return normRid(m[1]);
    }catch(_){}
    return "";
  }
  function setText(id, v){
    const el = document.getElementById(id);
    if(!el) return false;
    el.textContent = (v===0) ? "0" : (v ? String(v) : "—");
    return true;
  }
  function fmtBySev(bySev){
    if(!bySev) return "";
    const order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const out=[];
    for(const k of order){ if(bySev[k]!==undefined) out.push(k[0]+":"+bySev[k]); }
    return out.join(" ");
  }
  function pickTool(byTool, want){
    if(!byTool) return null;
    if(byTool[want]!==undefined) return byTool[want];
    const key = Object.keys(byTool).find(k => String(k||"").toUpperCase()===want.toUpperCase());
    return key ? byTool[key] : null;
  }

  async function fetchExtras(rid){
    if(!rid) return null;
    const u="/api/vsp/dashboard_v3_extras_v1?rid="+encodeURIComponent(rid);
    try{
      const r=await fetch(u,{cache:"no-store"});
      if(!r.ok) return null;
      const j=await r.json();
      return (j && j.ok) ? j : null;
    }catch(_){ return null; }
  }

  function apply(j){
    if(!j || !j.kpi) return false;
    const k=j.kpi||{};
    const byTool=j.by_tool||{};
    const bySev=j.by_sev||{};
    const total=k.total??0, eff=k.effective??0, degr=k.degraded??0, unk=k.unknown_count??0;
    const score=(k.score===undefined||k.score===null) ? "" : k.score;
    const verdict=(degr>0) ? "DEGRADED" : (total>0 ? "OK" : "EMPTY");
    const gate=(score!=="") ? (String(score)+"/100") : verdict;

    let ok=0;
    ok += setText("kpi-overall", verdict) ? 1:0;
    ok += setText("kpi-overall-sub", `total ${total} | eff ${eff} | degr ${degr} | unk ${unk}`) ? 1:0;
    ok += setText("kpi-gate", gate) ? 1:0;
    ok += setText("kpi-gate-sub", fmtBySev(bySev)) ? 1:0;

    const gtl=pickTool(byTool,"GITLEAKS");
    const cql=pickTool(byTool,"CODEQL");
    ok += setText("kpi-gitleaks", (gtl===null)?"NOT_RUN":gtl) ? 1:0;
    ok += setText("kpi-gitleaks-sub","GITLEAKS") ? 1:0;
    ok += setText("kpi-codeql", (cql===null)?"NOT_RUN":cql) ? 1:0;
    ok += setText("kpi-codeql-sub","CODEQL") ? 1:0;
    return ok>=2;
  }

  async function hydrate(){
    const rid=getRid();
    if(!rid) return;
    const j=await fetchExtras(rid);
    if(!j) return;
    apply(j);
  }

  // chạy sau DOM + retry vì pane hydrate có thể đến sau
  document.addEventListener("DOMContentLoaded", ()=>{
    hydrate();
    setTimeout(hydrate, 250);
    setTimeout(hydrate, 800);
    setTimeout(hydrate, 1600);
    setInterval(hydrate, 2000);
  });
})();
</script>
"""

# inject before </body>
if "</body>" in s.lower():
    s = re.sub(r"(?i)\s*</body>\s*", ins + "\n</body>\n", s, count=1)
else:
    s = s + "\n" + ins + "\n"

t.write_text(s, encoding="utf-8")
print("[OK] injected", marker, "into", t)
PY

echo "[OK] patched template KPI inline extras"
