#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_extras_p1_v4_${TS}" && echo "[BACKUP] $F.bak_kpi_extras_p1_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

marker="VSP_DASH_KPI_FROM_EXTRAS_P1_V4"
if marker in s:
    print("[SKIP] marker exists:", marker)
    raise SystemExit(0)

ins = r'''
  // === VSP_DASH_KPI_FROM_EXTRAS_P1_V4 ===
  (function(){
    if(window.__VSP_DASH_KPI_FROM_EXTRAS_P1_V4) return;
    window.__VSP_DASH_KPI_FROM_EXTRAS_P1_V4 = 1;

    function normRid(x){
      try{
        x = String(x || "").trim();
        x = x.replace(/^RUN[_\-\s]+/i, "");
        x = x.replace(/^RID[:\s]+/i, "");
        const m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
        if(m && m[1]) return m[1];
        return x.replace(/\s+/g, "_");
      }catch(_){ return ""; }
    }

    function getRidBestEffort(){
      // 1) global state (if any)
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

      // 2) header text contains "RID:"
      try{
        const body = document.body ? (document.body.innerText || "") : "";
        const m = body.match(/RID:\s*(VSP_CI_\d{8}_\d{6})/i);
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
        if(bySev[k] !== undefined) out.push(k + ":" + bySev[k]);
      }
      return out.join(" ");
    }

    function pickTool(byTool, want){
      if(!byTool) return null;
      if(byTool[want] !== undefined) return byTool[want];
      const key = Object.keys(byTool).find(k => String(k||"").toUpperCase() === want.toUpperCase());
      return key ? byTool[key] : null;
    }

    function applyExtras(rid, kpi){
      if(!kpi) return;
      const total = kpi.total ?? 0;
      const eff = kpi.effective ?? 0;
      const degr = kpi.degraded ?? 0;
      const unk = kpi.unknown_count ?? 0;
      const score = (kpi.score === undefined || kpi.score === null) ? "" : kpi.score;

      const status = (degr > 0) ? "DEGRADED" : (total > 0 ? "OK" : "EMPTY");

      // commercial 4tabs KPI ids (exist in template)
      setText("kpi-overall", score !== "" ? (score + "/100") : status);
      setText("kpi-overall-sub", `total ${total} | eff ${eff} | degr ${degr} | unk ${unk}`);

      setText("kpi-gate", status);
      setText("kpi-gate-sub", fmtBySev(kpi.by_sev));

      const gtl = pickTool(kpi.by_tool, "GITLEAKS");
      setText("kpi-gitleaks", (gtl === null) ? "NOT_RUN" : gtl);
      setText("kpi-gitleaks-sub", "GITLEAKS");

      const cql = pickTool(kpi.by_tool, "CODEQL");
      setText("kpi-codeql", (cql === null) ? "NOT_RUN" : cql);
      setText("kpi-codeql-sub", "CODEQL");

      // if dashboard_2025 ids exist, also fill
      setText("kpi-total", total);
      setText("kpi-effective", eff);
      setText("kpi-degraded", degr);
      setText("kpi-score", score);
    }

    function fetchExtras(rid){
      const u = "/api/vsp/dashboard_v3_extras_v1?rid=" + encodeURIComponent(rid || "");
      return fetch(u, {cache:"no-store"})
        .then(r => r.ok ? r.json() : null)
        .then(j => (j && j.ok && j.kpi) ? j.kpi : null)
        .catch(_ => null);
    }

    let lastRid = "";
    function hydrate(force){
      const rid = getRidBestEffort();
      if(!rid) return;
      if(!force && rid === lastRid) return;
      lastRid = rid;
      fetchExtras(rid).then(kpi => { if(kpi) applyExtras(rid, kpi); });
    }

    // run on navigation + periodic
    window.addEventListener("hashchange", () => setTimeout(() => hydrate(true), 120));
    setTimeout(() => hydrate(true), 300);
    setInterval(() => hydrate(false), 1500);
    setInterval(() => hydrate(true), 15000);
  })();
  // === /VSP_DASH_KPI_FROM_EXTRAS_P1_V4 ===
'''

if "'use strict';" in s:
    s = s.replace("'use strict';", "'use strict';\n"+ins, 1)
elif '"use strict";' in s:
    s = s.replace('"use strict";', '"use strict";\n'+ins, 1)
else:
    s = ins + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected:", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
