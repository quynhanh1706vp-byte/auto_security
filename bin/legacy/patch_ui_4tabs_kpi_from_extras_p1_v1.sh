#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_extras_${TS}" && echo "[BACKUP] $F.bak_kpi_extras_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_4TABS_KPI_FROM_EXTRAS_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r'''
/* === VSP_4TABS_KPI_FROM_EXTRAS_P1_V1 === */
(function(){
  if(window.__VSP_4TABS_KPI_FROM_EXTRAS_P1_V1) return;
  window.__VSP_4TABS_KPI_FROM_EXTRAS_P1_V1 = 1;

  function normRid(x){
    try{
      x = String(x||"").trim();
      x = x.replace(/^RUN[_\-\s]+/i, "");
      x = x.replace(/^RID[:\s]+/i, "");
      const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return m[1];
      return x.replace(/\s+/g,"_");
    }catch(_){ return ""; }
  }

  function getRid(){
    try{
      const st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE;
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
      const t = document.body ? (document.body.innerText || "") : "";
      const m = t.match(/RID:\s*(VSP_CI_\d{8}_\d{6})/i);
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
    const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    const out = [];
    for(const k of order){
      if(bySev[k] !== undefined) out.push(k[0] + ":" + bySev[k]);
    }
    return out.join(" ");
  }

  async function fetchExtras(rid){
    if(!rid) return null;
    const u = "/api/vsp/dashboard_v3_extras_v1?rid=" + encodeURIComponent(rid);
    try{
      const r = await fetch(u, {cache:"no-store"});
      if(!r.ok) return null;
      const j = await r.json();
      if(j && j.ok) return j;
    }catch(_){}
    return null;
  }

  function applyExtras(j){
    const k = (j && j.kpi) ? j.kpi : {};
    const byTool = j.by_tool || {};
    const bySev  = j.by_sev  || {};

    const total = k.total ?? 0;
    const eff   = k.effective ?? 0;
    const degr  = k.degraded ?? 0;
    const unk   = k.unknown_count ?? 0;
    const score = (k.score===undefined || k.score===null) ? "" : k.score;

    const verdict = (degr > 0) ? "DEGRADED" : (total > 0 ? "OK" : "EMPTY");
    const gateTxt = (score !== "") ? (String(score) + "/100") : verdict;

    setText("kpi-overall", verdict);
    setText("kpi-overall-sub", `total ${total} | eff ${eff} | degr ${degr} | unk ${unk}`);
    setText("kpi-gate", gateTxt);
    setText("kpi-gate-sub", fmtBySev(bySev));

    const gtl = (byTool.GITLEAKS !== undefined) ? byTool.GITLEAKS : null;
    const cql = (byTool.CODEQL  !== undefined) ? byTool.CODEQL  : null;
    setText("kpi-gitleaks", (gtl===null) ? "NOT_RUN" : gtl);
    setText("kpi-gitleaks-sub", "GITLEAKS");
    setText("kpi-codeql", (cql===null) ? "NOT_RUN" : cql);
    setText("kpi-codeql-sub", "CODEQL");
  }

  let lastRid = "";
  async function hydrate(force){
    const rid = getRid();
    if(!rid) return;
    if(!force && rid === lastRid) return;
    lastRid = rid;

    const j = await fetchExtras(rid);
    if(j) applyExtras(j);
  }

  window.addEventListener("hashchange", () => setTimeout(() => hydrate(true), 120));
  setTimeout(() => hydrate(true), 200);
  setInterval(() => hydrate(false), 1500);
})();
'''

# inject after use strict if possible
if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
elif '"use strict";' in s:
    s = s.replace('"use strict";', '"use strict";\n'+ins, 1)
else:
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
