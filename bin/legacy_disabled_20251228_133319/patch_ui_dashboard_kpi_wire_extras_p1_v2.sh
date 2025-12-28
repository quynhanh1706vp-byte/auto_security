#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_wire_${TS}" && echo "[BACKUP] $F.bak_kpi_wire_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASHBOARD_KPI_WIRE_EXTRAS_P1_V2"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

# 1) best-effort: remove the broken "await fetchDashboardExtras(...)" if it exists
s = re.sub(
    r'(^\s*const\s+kpiExtras\s*=\s*await\s+fetchDashboardExtras\s*\([^\)]*\)\s*;?\s*$)',
    r'// [AUTO-REMOVED] broken await (wired by VSP_DASHBOARD_KPI_WIRE_EXTRAS_P1_V2)',
    s,
    flags=re.M
)
s = re.sub(
    r'(^\s*let\s+kpiExtras\s*=\s*await\s+fetchDashboardExtras\s*\([^\)]*\)\s*;?\s*$)',
    r'// [AUTO-REMOVED] broken await (wired by VSP_DASHBOARD_KPI_WIRE_EXTRAS_P1_V2)',
    s,
    flags=re.M
)

ins = r'''
  // === VSP_DASHBOARD_KPI_WIRE_EXTRAS_P1_V2 ===
  (function(){
    if(window.__VSP_KPI_EXTRAS_WIRED_P1_V2) return;
    window.__VSP_KPI_EXTRAS_WIRED_P1_V2 = 1;

    function _ridFromState(){
      try{
        const candidates = [
          window.__vsp_rid_state,
          window.VSP_RID_STATE,
          window.VSP_RID_STATE_V1,
          window.__VSP_RID_STATE
        ].filter(Boolean);

        for(const st of candidates){
          if(typeof st.get === "function"){
            const r = st.get();
            if(r && (r.rid || r.run_id)) return (r.rid || r.run_id);
          }
          if(st && (st.rid || st.run_id)) return (st.rid || st.run_id);
          if(st && st.state && (st.state.rid || st.state.run_id)) return (st.state.rid || st.state.run_id);
        }
      }catch(_){}
      return "";
    }

    function getRidBestEffort(){
      const r0 = _ridFromState();
      if(r0) return String(r0).trim();

      // try DOM (some headers render RID: XXX)
      try{
        const body = document.body ? (document.body.innerText || "") : "";
        const m = body.match(/RID:\s*(VSP_[A-Z0-9_]+)/);
        if(m && m[1]) return m[1];
      }catch(_){}
      return "";
    }

    function setText(id, val){
      const el = document.getElementById(id);
      if(!el) return;
      el.textContent = (val===undefined || val===null || val==="") ? "—" : String(val);
    }

    function setSub(id, val){
      const el = document.getElementById(id);
      if(!el) return;
      el.textContent = (val===undefined || val===null) ? "" : String(val);
    }

    function fmtSev(bySev){
      if(!bySev) return "";
      const order = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const parts = [];
      for(const k of order){
        if(bySev[k]!==undefined && bySev[k]!==null) parts.push(k+":"+bySev[k]);
      }
      return parts.join(" ");
    }

    function pickTool(byTool, want){
      if(!byTool) return null;
      if(byTool[want]!==undefined) return byTool[want];
      try{
        const key = Object.keys(byTool).find(k => String(k||"").toUpperCase() === String(want).toUpperCase());
        if(key) return byTool[key];
      }catch(_){}
      return null;
    }

    function applyExtras(rid, kpi){
      if(!kpi) return;

      const total = kpi.total || 0;
      const eff = kpi.effective || 0;
      const degr = kpi.degraded || 0;
      const unk  = (kpi.unknown_count===undefined || kpi.unknown_count===null) ? "" : kpi.unknown_count;
      const score = (kpi.score===undefined || kpi.score===null) ? "" : kpi.score;

      const status = (degr>0) ? "DEGRADED" : (total>0 ? "OK" : "EMPTY");

      // These KPI ids are used by vsp_4tabs_commercial_v1.html (commercial panel)
      setText("kpi-overall", score!=="" ? (score + "/100") : status);
      setSub ("kpi-overall-sub", "total " + total + " | eff " + eff + " | degr " + degr + (unk!=="" ? (" | unk "+unk) : ""));

      setText("kpi-gate", status);
      setSub ("kpi-gate-sub", fmtSev(kpi.by_sev));

      const gtl = pickTool(kpi.by_tool, "GITLEAKS");
      setText("kpi-gitleaks", (gtl===null || gtl===undefined) ? "NOT_RUN" : gtl);
      setSub ("kpi-gitleaks-sub", (gtl===null || gtl===undefined) ? "tool=GITLEAKS missing" : ("tool=GITLEAKS | rid=" + rid));

      const cql = pickTool(kpi.by_tool, "CODEQL");
      setText("kpi-codeql", (cql===null || cql===undefined) ? "NOT_RUN" : cql);
      setSub ("kpi-codeql-sub", (cql===null || cql===undefined) ? "tool=CODEQL missing" : ("tool=CODEQL | rid=" + rid));
    }

    function fetchExtras(rid){
      const u = "/api/vsp/dashboard_v3_extras_v1?rid=" + encodeURIComponent(rid||"");
      return fetch(u, {cache:"no-store"})
        .then(r => r.ok ? r.json() : null)
        .then(j => (j && j.ok && j.kpi) ? j.kpi : null)
        .catch(_ => null);
    }

    let lastRid = "";
    function tick(force){
      const rid = getRidBestEffort();
      if(!rid) return;
      if(!force && rid === lastRid) return;
      lastRid = rid;

      fetchExtras(rid).then(kpi => {
        if(kpi) applyExtras(rid, kpi);
      });
    }

    window.addEventListener("hashchange", function(){ setTimeout(function(){ tick(true); }, 150); });
    document.addEventListener("visibilitychange", function(){ if(!document.hidden) setTimeout(function(){ tick(true); }, 150); });

    // first paint + periodic refresh
    setTimeout(function(){ tick(true); }, 300);
    setInterval(function(){ tick(false); }, 1500);
    setInterval(function(){ tick(true); }, 15000);
  })();
'''

# inject right after 'use strict';
if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
elif '"use strict";' in s:
    s = s.replace('"use strict";', '"use strict";\n'+ins, 1)
else:
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched dashboard KPI wire extras P1 v2")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
