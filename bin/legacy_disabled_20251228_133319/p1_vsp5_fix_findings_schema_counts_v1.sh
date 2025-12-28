#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_fix_findings_schema_${TS}"
echo "[BACKUP] ${JS}.bak_fix_findings_schema_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_VSP5_FIX_FINDINGS_SCHEMA_COUNTS_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

patch_block = r"""
/* VSP_P1_VSP5_FIX_FINDINGS_SCHEMA_COUNTS_V1
   - robust parse findings_unified.json: JSON or JSONL, nested arrays
   - derive severity counts from findings when gate summary has none
   - update donut + KPI pills + Top Findings
*/
(()=> {
  try{
    if (window.__vsp_p1_fix_findings_schema_counts_v1) return;
    window.__vsp_p1_fix_findings_schema_counts_v1 = true;

    const isDash = ()=> (location && location.pathname && location.pathname.indexOf("/vsp5") === 0);
    if (!isDash()) return;

    const $ = (id)=> document.getElementById(id);

    function normSev(v){
      const s = (v||"").toString().toUpperCase();
      if (["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].includes(s)) return s;
      if (s === "WARNING") return "MEDIUM";
      if (s === "ERROR") return "HIGH";
      return "INFO";
    }

    function pickFirstArrayDeep(obj, depth=0){
      if (!obj || depth>4) return null;
      if (Array.isArray(obj)) return obj;
      if (typeof obj !== "object") return null;

      // common keys first (fast path)
      const keysPref = ["findings","items","results","data","rows","records","unified","findings_unified","findingsUnify","findings_list","list"];
      for (const k of keysPref){
        const v = obj[k];
        if (Array.isArray(v)) return v;
      }
      // otherwise scan keys
      for (const k of Object.keys(obj)){
        const v = obj[k];
        if (Array.isArray(v)) return v;
        const deep = pickFirstArrayDeep(v, depth+1);
        if (deep) return deep;
      }
      return null;
    }

    function parseFindingsText(txt){
      // try JSON first
      try{
        const j = JSON.parse(txt);
        const arr = pickFirstArrayDeep(j, 0);
        if (Array.isArray(arr)) return arr;
        return [];
      }catch(e){
        // JSONL fallback: parse per line
        const out = [];
        const lines = (txt||"").split(/\r?\n/);
        for (let i=0;i<lines.length;i++){
          const ln = lines[i].trim();
          if (!ln) continue;
          if (ln[0] !== "{") continue;
          try{
            const o = JSON.parse(ln);
            out.push(o);
          }catch(_){}
          if (out.length >= 5000) break;
        }
        return out;
      }
    }

    function calcCounts(findings){
      const c = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      for (const f of (findings||[])){
        const sev = normSev(f?.severity || f?.sev || f?.level || f?.priority);
        c[sev] = (c[sev]||0) + 1;
      }
      return c;
    }

    // update KPI pills if exist (from earlier injected dashboard)
    function updateKpiPills(counts){
      const set = (id, v)=>{ const el=$(id); if(el) el.textContent = v; };
      set("vsp_dash_c_critical", `CRIT: ${counts.CRITICAL||0}`);
      set("vsp_dash_c_high",     `HIGH: ${counts.HIGH||0}`);
      set("vsp_dash_c_medium",   `MED: ${counts.MEDIUM||0}`);
      set("vsp_dash_c_low",      `LOW: ${counts.LOW||0}`);
      set("vsp_dash_c_info",     `INFO: ${counts.INFO||0}`);
      set("vsp_dash_c_trace",    `TRACE: ${counts.TRACE||0}`);
    }

    // hook: when DashFull logs schema mismatch, re-run with robust parser
    const _log = console.log.bind(console);
    console.log = (...args)=>{
      try{
        if (args && args[0] && typeof args[0] === "string" && args[0].indexOf("[VSP][DashFull] findings parsed=0") !== -1){
          // kick an async repair pass
          setTimeout(async ()=>{
            try{
              const meta = await (await fetch("/api/vsp/runs?_ts="+Date.now(), {cache:"no-store"})).json();
              const rid = meta?.rid_latest_gate_root || meta?.rid_latest || meta?.rid_last_good || meta?.rid_latest_findings || "";
              if (!rid) return;

              const r = await fetch(`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_ts=${Date.now()}`, {cache:"no-store"});
              if (!r.ok) return;
              const txt = await r.text();
              const findings = parseFindingsText(txt);

              // counts from findings (fallback)
              const counts = calcCounts(findings);
              updateKpiPills(counts);

              // if donut exists from DashFull, try to repaint it simply (donut is inside DashFull; we just force refresh by triggering its interval)
              // But we at least update the "Top Findings" table directly.
              const rows = $("vsp_findings_rows");
              const metaEl = $("vsp_findings_meta");
              if (metaEl) metaEl.textContent = `items=${findings.length} • rid=${rid.slice(0,24)}…`;

              if (!rows) return;
              if (!findings.length){
                rows.innerHTML = `<tr><td colspan="4" style="opacity:.7;">findings_unified.json parsed=0 (even with JSONL/nested). Check file format.</td></tr>`;
                return;
              }

              // sort by severity weight
              const w = {CRITICAL:0,HIGH:1,MEDIUM:2,LOW:3,INFO:4,TRACE:5};
              const top = findings.slice().sort((a,b)=>{
                const sa = w[normSev(a?.severity||a?.sev||a?.level)] ?? 9;
                const sb = w[normSev(b?.severity||b?.sev||b?.level)] ?? 9;
                if (sa!==sb) return sa-sb;
                const ta = (a?.tool||a?.scanner||a?.engine||"").toString();
                const tb = (b?.tool||b?.scanner||b?.engine||"").toString();
                return ta.localeCompare(tb);
              }).slice(0,12);

              const esc = (s)=> (s==null? "" : String(s)).replace(/[&<>"']/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));
              const sevBadge = (sev)=>{
                const S = normSev(sev);
                return `<span class="sev_badge sev_${S}">${S}</span>`;
              };

              rows.innerHTML = top.map(f=>{
                const sev = normSev(f?.severity||f?.sev||f?.level||f?.priority);
                const tool = (f?.tool||f?.scanner||f?.engine||f?.source||"—").toString();
                const title = (f?.title||f?.name||f?.message||f?.desc||f?.description||f?.summary||"—").toString();
                const rule = (f?.rule_id||f?.rule||f?.check_id||f?.id||f?.cwe||f?.owasp||"").toString();
                const file = (f?.path||f?.file||f?.file_path||f?.location||f?.filename||"—").toString();
                const line = (f?.line!=null? f.line : (f?.start_line!=null? f.start_line : null));
                const file2 = (line!=null) ? `${file}:${line}` : file;
                const t = rule ? `${title} • ${rule}` : title;
                return `<tr>
                  <td>${sevBadge(sev)}</td>
                  <td style="opacity:.9;">${esc(tool)}</td>
                  <td style="opacity:.92;">${esc(t).slice(0,220)}</td>
                  <td style="opacity:.85;font-family:ui-monospace,monospace;font-size:11.5px;">${esc(file2).slice(0,180)}</td>
                </tr>`;
              }).join("");

              _log("[VSP][FixFindings] repaired schema; parsed=", findings.length, "counts=", counts);
            }catch(e){
              console.warn("[VSP][FixFindings] repair err", e);
            }
          }, 50);
        }
      }catch(e){}
      return _log(...args);
    };

    console.log("[VSP][FixFindings] installed");
  }catch(e){
    console.warn("[VSP][FixFindings] init failed", e);
  }
})();
"""

p.write_text(s.rstrip() + "\n\n" + patch_block + "\n", encoding="utf-8")
print("[OK] appended findings schema+counts fixer")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Open /vsp5 and HARD reload (Ctrl+Shift+R). Expect console: [VSP][FixFindings] installed"
