#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need python3; need grep; need sed
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

JS="static/js/vsp_dashboard_gate_story_v1.js"
WSGI="wsgi_vsp_ui_gateway.py"
PANELS="static/js/vsp_dashboard_commercial_panels_v1.js"

[ -f "$JS" ]   || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS"   "${JS}.bak_recover_${TS}"
cp -f "$WSGI" "${WSGI}.bak_panels_${TS}"
echo "[BACKUP] ${JS}.bak_recover_${TS}"
echo "[BACKUP] ${WSGI}.bak_panels_${TS}"

echo "== [1/3] Recover GateStory to last-known-good (skip broken P1 panel injections) =="

GOOD=""
# candidates: newest first
CANDS="$(ls -1t ${JS}.bak_* 2>/dev/null || true)"
if [ -n "${CANDS}" ]; then
  while read -r f; do
    [ -z "$f" ] && continue
    # skip panel-injected backups
    if grep -qE "VSP_P1_DASHBOARD_P1_PANELS|DashP1V|RIDWAIT|MULTIFINDINGS|unwrap fix|normFindingsPayload" "$f" 2>/dev/null; then
      continue
    fi
    if [ "$node_ok" = "1" ]; then
      node --check "$f" >/dev/null 2>&1 || continue
    fi
    GOOD="$f"
    break
  done <<< "$CANDS"
fi

if [ -n "$GOOD" ]; then
  cp -f "$GOOD" "$JS"
  echo "[OK] recovered GateStory from: $GOOD"
else
  echo "[WARN] cannot find clean backup (keep current GateStory). We'll still add external panels."
fi

if [ "$node_ok" = "1" ]; then
  node --check "$JS" && echo "[OK] node --check GateStory OK" || echo "[WARN] GateStory still has syntax issue (panels will still be independent)."
fi

echo "== [2/3] Write external Commercial Panels JS (independent, robust unwrap) =="

python3 - <<'PY'
from pathlib import Path
import textwrap, time

p = Path("static/js/vsp_dashboard_commercial_panels_v1.js")
ts = time.strftime("%Y%m%d_%H%M%S")

code = r"""
/* VSP_P1_DASHCOMM_PANELS_V1 (external panels; do NOT depend on GateStory internals) */
(()=> {
  if (window.__vsp_p1_dashcomm_panels_v1) return;
  window.__vsp_p1_dashcomm_panels_v1 = true;

  const log  = (...a)=>console.log("[DashCommPanelsV1]", ...a);
  const warn = (...a)=>console.warn("[DashCommPanelsV1]", ...a);
  const err  = (...a)=>console.error("[DashCommPanelsV1]", ...a);

  const W = { CRITICAL: 5, HIGH: 4, MEDIUM: 3, LOW: 2, INFO: 1, TRACE: 0 };

  function normSev(x){
    const s = (x==null ? "" : String(x)).trim().toUpperCase();
    if (!s) return "INFO";
    if (s.startsWith("CRIT")) return "CRITICAL";
    if (s.startsWith("HIGH")) return "HIGH";
    if (s.startsWith("MED"))  return "MEDIUM";
    if (s.startsWith("LOW"))  return "LOW";
    if (s.startsWith("INFO")) return "INFO";
    if (s.startsWith("TRACE"))return "TRACE";
    return "INFO";
  }

  function sleep(ms){ return new Promise(r=>setTimeout(r, ms)); }

  async function fetchJSON(url, timeoutMs=20000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, { credentials:"same-origin", signal: ctrl.signal });
      if (!r.ok) throw new Error(`HTTP ${r.status} for ${url}`);
      // IMPORTANT: read body once
      return await r.json();
    } finally {
      clearTimeout(t);
    }
  }

  function unwrapRuns(j){
    if (Array.isArray(j)) return j;
    if (j && typeof j === "object"){
      if (Array.isArray(j.runs)) return j.runs;
      if (Array.isArray(j.items)) return j.items;
      if (Array.isArray(j.data)) return j.data;
    }
    return [];
  }

  function unwrapFindingsPayload(j){
    if (Array.isArray(j)) return { meta:null, findings:j };
    if (j && typeof j === "object"){
      if (Array.isArray(j.findings)) return { meta:(j.meta||j.metadata||null), findings:j.findings };
      if (Array.isArray(j.items))    return { meta:(j.meta||j.metadata||null), findings:j.items };
      if (Array.isArray(j.data))     return { meta:(j.meta||j.metadata||null), findings:j.data };
    }
    return null;
  }

  function countsBySeverity(meta, findings){
    const base = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
    const by = meta && (meta.counts_by_severity || meta.countsBySeverity || meta.counts_by_level || meta.counts);
    if (by && typeof by === "object"){
      for (const [k,v] of Object.entries(by)){
        base[normSev(k)] = Number(v)||0;
      }
      return base;
    }
    for (const f of (findings||[])){
      const sev = normSev(f && (f.severity || f.level || f.priority || f.impact));
      base[sev] = (base[sev]||0) + 1;
    }
    return base;
  }

  function pickRIDFromDOM(){
    const t = (document.body && (document.body.innerText||"")) || "";
    // common rid patterns
    let m = t.match(/VSP_[A-Z0-9]+_RUN_\d{8}_\d{6}/);
    if (m && m[0]) return m[0];
    m = t.match(/RUN_\d{8}_\d{6}/);
    if (m && m[0]) return m[0];
    return null;
  }

  async function resolveRID(){
    // try known globals if GateStory sets any (safe)
    const keys = [
      "__vsp_gate_root_rid","__VSP_GATE_ROOT_RID","__vsp_rid","VSP_RID",
      "vsp_rid","gate_root_rid","rid_latest_gate_root","rid_last_good"
    ];
    for (const k of keys){
      const v = window[k];
      if (typeof v === "string" && v.length >= 10) return v;
    }

    // DOM scrape
    const domRID = pickRIDFromDOM();
    if (domRID) return domRID;

    // fallback runs api
    try{
      const j = await fetchJSON("/api/vsp/runs?limit=1&offset=0", 15000);
      const runs = unwrapRuns(j);
      const r0 = runs[0] || {};
      return r0.rid || r0.run_id || r0.id || null;
    } catch(e){
      warn("runs fallback failed", e);
    }
    return null;
  }

  async function loadRunFileAllow(rid, path, timeoutMs=20000){
    const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
    return await fetchJSON(u, timeoutMs);
  }

  async function loadFindingsBestEffort(rid){
    const paths = [
      "findings_unified.json",
      "reports/findings_unified.json"
    ];
    let lastErr = null;
    for (const p of paths){
      try{
        const j = await loadRunFileAllow(rid, p, 25000);
        return { path: p, payload: j };
      } catch(e){
        lastErr = e;
      }
    }
    throw lastErr || new Error("findings not found");
  }

  function mk(tag, attrs={}, children=[]){
    const e = document.createElement(tag);
    for (const [k,v] of Object.entries(attrs||{})){
      if (k === "style" && v && typeof v === "object"){
        for (const [sk,sv] of Object.entries(v)) e.style[sk] = sv;
      } else if (k.startsWith("on") && typeof v === "function"){
        e.addEventListener(k.slice(2), v);
      } else {
        e.setAttribute(k, String(v));
      }
    }
    for (const c of (children||[])){
      if (c == null) continue;
      if (typeof c === "string") e.appendChild(document.createTextNode(c));
      else e.appendChild(c);
    }
    return e;
  }

  function ensureHost(){
    let host = document.getElementById("vsp_p1_panels_root");
    if (host) return host;

    const anchor =
      document.getElementById("vsp5_root") ||
      document.querySelector("#vsp5_root") ||
      document.body;

    host = mk("div", { id:"vsp_p1_panels_root", style:{
      margin:"14px", padding:"12px",
      border:"1px solid rgba(255,255,255,.10)",
      borderRadius:"14px",
      background:"rgba(0,0,0,.18)"
    }});
    anchor.appendChild(host);
    return host;
  }

  function renderError(host, msg){
    host.innerHTML = "";
    host.appendChild(mk("div", { style:{
      padding:"10px 12px",
      borderRadius:"12px",
      border:"1px solid rgba(255,80,80,.45)",
      background:"rgba(120,20,20,.18)",
      color:"rgba(255,220,220,.92)",
      fontSize:"12px"
    }}, [msg]));
  }

  function render(host, rid, gateSum, meta, findings, findingsPath){
    host.innerHTML = "";

    const counts = countsBySeverity(meta, findings);

    const header = mk("div", { style:{display:"flex",justifyContent:"space-between",alignItems:"center",gap:"10px"} }, [
      mk("div", {}, [
        mk("div", { style:{fontSize:"13px",fontWeight:"700"} }, ["Commercial Panels"]),
        mk("div", { style:{fontSize:"12px",opacity:".85",marginTop:"2px"} }, [`RID: ${rid} • source: ${findingsPath}`]),
      ]),
      mk("div", { style:{display:"flex",gap:"8px",alignItems:"center"} }, [
        mk("button", { style:{
          cursor:"pointer", fontSize:"12px", padding:"6px 10px",
          borderRadius:"12px", border:"1px solid rgba(255,255,255,.14)",
          background:"rgba(255,255,255,.06)", color:"rgba(226,232,240,.94)"
        }, onclick: ()=>location.reload() }, ["Reload"]),
      ])
    ]);

    const kpiRow = mk("div", { style:{display:"flex",gap:"10px",flexWrap:"wrap",marginTop:"10px"} }, Object.entries(counts).map(([k,v])=>{
      return mk("div", { style:{
        minWidth:"110px", padding:"10px 12px", borderRadius:"14px",
        border:"1px solid rgba(255,255,255,.10)",
        background:"rgba(0,0,0,.16)"
      }}, [
        mk("div", { style:{fontSize:"11px",opacity:".85"} }, [k]),
        mk("div", { style:{fontSize:"16px",fontWeight:"800",marginTop:"2px"} }, [String(v)]),
      ]);
    }));

    // tool lane
    let toolLane = null;
    try{
      const byTool = gateSum && (gateSum.by_tool || gateSum.byTool || gateSum.tools);
      if (byTool && typeof byTool === "object"){
        const items = Object.entries(byTool).slice(0, 24).map(([tool, info])=>{
          const st = (info && (info.status || info.state || info.verdict)) || "";
          return mk("div", { style:{
            padding:"6px 10px",
            borderRadius:"999px",
            border:"1px solid rgba(255,255,255,.14)",
            background:"rgba(255,255,255,.06)",
            fontSize:"11px"
          }}, [`${tool}: ${st}`]);
        });
        toolLane = mk("div", { style:{display:"flex",gap:"8px",flexWrap:"wrap",marginTop:"10px"} }, items);
      }
    }catch(e){ /* ignore */ }

    // top findings
    const sorted = (findings||[]).slice(0).sort((a,b)=>{
      const sa = W[normSev(a && (a.severity||a.level))] || 0;
      const sb = W[normSev(b && (b.severity||b.level))] || 0;
      return sb - sa;
    }).slice(0, 12);

    const table = mk("table", { style:{
      width:"100%", borderCollapse:"separate", borderSpacing:"0 8px", marginTop:"10px"
    }}, [
      mk("thead", {}, [
        mk("tr", {}, [
          mk("th", { style:{textAlign:"left",fontSize:"11px",opacity:".85"} }, ["Sev"]),
          mk("th", { style:{textAlign:"left",fontSize:"11px",opacity:".85"} }, ["Tool"]),
          mk("th", { style:{textAlign:"left",fontSize:"11px",opacity:".85"} }, ["Rule"]),
          mk("th", { style:{textAlign:"left",fontSize:"11px",opacity:".85"} }, ["Title/Message"]),
        ])
      ]),
      mk("tbody", {}, sorted.map(f=>{
        const sev = normSev(f && (f.severity||f.level));
        const tool = (f && (f.tool||f.engine||f.source||f.scanner)) || "";
        const rule = (f && (f.rule_id||f.rule||f.check_id||f.check||f.id)) || "";
        const title = (f && (f.title||f.name||f.message||f.summary)) || "";
        return mk("tr", { style:{
          background:"rgba(0,0,0,.14)",
          border:"1px solid rgba(255,255,255,.08)"
        }}, [
          mk("td", { style:{padding:"8px 10px",fontSize:"12px",whiteSpace:"nowrap"} }, [sev]),
          mk("td", { style:{padding:"8px 10px",fontSize:"12px",maxWidth:"180px",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"} }, [String(tool)]),
          mk("td", { style:{padding:"8px 10px",fontSize:"12px",maxWidth:"220px",overflow:"hidden",textOverflow:"ellipsis",whiteSpace:"nowrap"} }, [String(rule)]),
          mk("td", { style:{padding:"8px 10px",fontSize:"12px"} }, [String(title)]),
        ]);
      }))
    ]);

    host.appendChild(header);
    host.appendChild(kpiRow);
    if (toolLane) host.appendChild(toolLane);
    host.appendChild(table);
  }

  async function main(){
    const host = ensureHost();
    host.innerHTML = `<div style="font-size:12px;opacity:.85">Loading commercial panels…</div>`;

    const rid = await resolveRID();
    if (!rid){
      renderError(host, "Cannot resolve RID (try /api/vsp/runs fallback failed).");
      return;
    }

    let gateSum = null;
    try { gateSum = await loadRunFileAllow(rid, "run_gate_summary.json", 20000); } catch(e){ /* optional */ }

    let res;
    try{
      res = await loadFindingsBestEffort(rid);
    }catch(e){
      renderError(host, `Findings not found via run_file_allow (rid=${rid}).`);
      return;
    }

    const u = unwrapFindingsPayload(res.payload);
    if (!u || !Array.isArray(u.findings)){
      renderError(host, "Findings payload shape mismatch (expected {meta,findings[]} or findings[]).");
      return;
    }

    render(host, rid, gateSum, u.meta, u.findings, res.path);
    log("rendered", { rid, findings: u.findings.length, has_counts: !!(u.meta && u.meta.counts_by_severity) });
  }

  // run after GateStory paints (but independent)
  (async()=>{
    for (let i=0;i<20;i++){
      if (document.body && document.body.innerText && document.body.innerText.includes("VSP")) break;
      await sleep(80);
    }
    try { await main(); } catch(e){ err("fatal", e); }
  })();

})();
"""
p.write_text(code, encoding="utf-8")
print(f"[OK] wrote {p} (len={len(code)})")
PY

if [ "$node_ok" = "1" ]; then
  node --check "$PANELS" && echo "[OK] node --check panels OK"
fi

echo "== [3/3] Patch /vsp5 HTML to include panels script (after GateStory) =="

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_DASHCOMM_PANELS_V1_WSGI_INCLUDE"
if marker in s:
    print("[OK] wsgi already patched")
else:
    # insert after gate_story include, reusing same ?v=...
    pat = r'(<script\s+src="/static/js/vsp_dashboard_gate_story_v1\.js\?v=(\d+)"></script>)'
    if re.search(pat, s):
        s2 = re.sub(pat,
            r'\1\n  <!-- %s -->\n  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v=\2"></script>' % marker,
            s, count=1)
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched wsgi: inserted panels include after GateStory")
    else:
        print("[WARN] cannot find GateStory include in wsgi (no changes made).")
PY

python3 -m py_compile "$WSGI" && echo "[OK] py_compile WSGI OK"

echo
echo "[DONE] Next steps:"
echo "  1) restart UI (systemd/gunicorn)"
echo "  2) HARD refresh /vsp5 (Ctrl+Shift+R)"
echo
echo "[VERIFY] HTML includes panels:"
echo "  curl -fsS http://127.0.0.1:8910/vsp5 | grep -nE \"gate_story_v1|commercial_panels_v1\" || true"
echo
echo "[VERIFY] JS syntax:"
echo "  node --check static/js/vsp_dashboard_gate_story_v1.js && node --check static/js/vsp_dashboard_commercial_panels_v1.js"
