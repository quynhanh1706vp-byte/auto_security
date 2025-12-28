#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p482f_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "${F}.bak_p482f_${TS}"
echo "[OK] backup => ${F}.bak_p482f_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P482F_RUNS_LIST_V3_FORCE_RENDER_HIDE_LEGACY_V1"
if MARK in s:
    print("[OK] already patched P482f (marker found)")
    raise SystemExit(0)

js = r"""
/* ===== {MARK} =====
 * Commercial Runs: hide legacy list/header, render Runs List V3 from /api/vsp/runs
 * - keeps Scan/Start Run block intact (RUN button later)
 * - resilient selectors (no reliance on legacy table existing)
 */
(function(){
  const TAG = "[P482f]";
  const API = "/api/vsp/runs?limit=250&offset=0";
  const LS_KEYS = ["VSP_PIN_RID","VSP_RID","VSP_LAST_RID","RID","vsp_rid"];

  function log(){ try{ console.log.apply(console, [TAG].concat([].slice.call(arguments))); }catch(e){} }

  function qsa(sel, root){ try{ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }catch(e){ return []; } }
  function qs(sel, root){ try{ return (root||document).querySelector(sel); }catch(e){ return null; } }

  function textIncludes(el, needle){
    try{
      const t = (el && (el.innerText||el.textContent)||"").toLowerCase();
      return t.indexOf(needle.toLowerCase()) >= 0;
    }catch(e){ return false; }
  }

  function hideEl(el){
    if(!el) return;
    el.style.display = "none";
    el.setAttribute("data-vsp-hidden", "1");
  }

  function findByText(needle){
    const cands = qsa("div,section,article,p,span");
    for(const el of cands){
      if(textIncludes(el, needle)) return el;
    }
    return null;
  }

  function ensureStyle(){
    if(qs("#vsp_runs_v3_style")) return;
    const st = document.createElement("style");
    st.id = "vsp_runs_v3_style";
    st.textContent = `
      .vsp-runs-v3-wrap{ margin: 10px 0 12px 0; }
      .vsp-runs-v3-toolbar{ position: sticky; top: 8px; z-index: 5; backdrop-filter: blur(6px); }
      .vsp-runs-v3-bar{ display:flex; gap:8px; align-items:center; justify-content:space-between; padding:10px 12px; border-radius:12px;
        border:1px solid rgba(255,255,255,.08); background: rgba(10,14,24,.55); }
      .vsp-runs-v3-left{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp-runs-v3-chip{ font-size:12px; padding:4px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.10);
        color: rgba(255,255,255,.86); cursor:pointer; user-select:none; }
      .vsp-runs-v3-chip[data-on="1"]{ border-color: rgba(255,255,255,.28); background: rgba(255,255,255,.06); }
      .vsp-runs-v3-input{ min-width: 280px; max-width: 520px; width: 36vw;
        font-size:12px; padding:6px 10px; border-radius:10px; outline:none;
        border:1px solid rgba(255,255,255,.10); background: rgba(0,0,0,.25); color: rgba(255,255,255,.90); }
      .vsp-runs-v3-right{ display:flex; gap:8px; align-items:center; }
      .vsp-runs-v3-sel{ font-size:12px; padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.10);
        background: rgba(0,0,0,.25); color: rgba(255,255,255,.90); }
      .vsp-runs-v3-btn{ font-size:12px; padding:6px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.10);
        background: rgba(255,255,255,.05); color: rgba(255,255,255,.90); cursor:pointer; }
      .vsp-runs-v3-tablewrap{ margin-top:10px; border-radius:12px; overflow:hidden; border:1px solid rgba(255,255,255,.08); }
      .vsp-runs-v3-table{ width:100%; border-collapse: collapse; }
      .vsp-runs-v3-table thead th{ font-size:12px; text-align:left; padding:10px 10px; color: rgba(255,255,255,.70);
        background: rgba(255,255,255,.03); border-bottom:1px solid rgba(255,255,255,.08); }
      .vsp-runs-v3-table tbody td{ font-size:12px; padding:9px 10px; border-bottom:1px solid rgba(255,255,255,.06);
        color: rgba(255,255,255,.85); vertical-align: top; }
      .vsp-runs-v3-table tbody tr:hover td{ background: rgba(255,255,255,.03); }
      .vsp-runs-v3-actions{ display:flex; gap:6px; flex-wrap:wrap; }
      .vsp-runs-v3-mini{ font-size:11px; padding:4px 8px; border-radius:10px; border:1px solid rgba(255,255,255,.12);
        background: rgba(255,255,255,.04); color: rgba(255,255,255,.88); cursor:pointer; text-decoration:none; }
      .vsp-runs-v3-muted{ color: rgba(255,255,255,.55); }
    `;
    document.head.appendChild(st);
  }

  function setRid(rid){
    try{
      LS_KEYS.forEach(k => { try{ localStorage.setItem(k, String(rid)); }catch(e){} });
      log("set RID =>", rid);
    }catch(e){}
  }

  function normStatus(x){
    const s = String(x||"").toUpperCase();
    if(!s) return "UNKNOWN";
    if(["OK","GREEN","PASS","PASSED"].includes(s)) return "OK";
    if(["WARN","AMBER"].includes(s)) return "WARN";
    if(["FAIL","RED","ERROR","FAILED"].includes(s)) return "FAIL";
    if(["UNKNOWN","NA","N/A","NONE"].includes(s)) return "UNKNOWN";
    return s;
  }

  function pick(obj, keys, dflt){
    for(const k of keys){
      if(obj && obj[k] != null && obj[k] !== "") return obj[k];
    }
    return dflt;
  }

  function pickDate(obj){
    const v = pick(obj, ["date","ts","time","started_at","ended_at","created_at"], "");
    if(!v) return "";
    // already looks like "2025-12-28 07:..." or ISO => keep
    return String(v).replace("T"," ").replace("Z","");
  }

  function hideLegacyRunsList(){
    // Hide legacy “No runs found” message only (keep Scan/Start Run)
    const noRuns = findByText("No runs found");
    if(noRuns) hideEl(noRuns);

    const noRuns2 = findByText("This environment has no run history");
    if(noRuns2) hideEl(noRuns2);

    // Hide legacy header row that shows: RID OVERALL CSV HTML SARIF SUMMARY ACTIONS
    const blocks = qsa("div,section,article");
    for(const el of blocks){
      const t = (el.innerText||"").trim().replace(/\s+/g," ");
      if(t === "RID OVERALL CSV HTML SARIF SUMMARY ACTIONS"){
        hideEl(el);
      }
    }
  }

  function findInsertPoint(){
    // Prefer inserting before “Scan / Start Run” block
    const scan = findByText("Scan / Start Run");
    if(scan){
      // walk up a bit to get a stable container
      let node = scan;
      for(let i=0;i<6 && node && node.parentElement;i++){
        if(node.classList && (node.classList.contains("card") || node.classList.contains("panel"))) break;
        node = node.parentElement;
      }
      return { parent: (scan.parentElement || document.body), before: scan };
    }
    // fallback: main content
    const main = qs("main") || qs("#content") || qs(".content") || document.body;
    return { parent: main, before: null };
  }

  function buildFrame(){
    ensureStyle();
    hideLegacyRunsList();

    if(qs("#vsp_runs_v3_wrap")) return;

    const ins = findInsertPoint();
    const wrap = document.createElement("div");
    wrap.id = "vsp_runs_v3_wrap";
    wrap.className = "vsp-runs-v3-wrap";

    wrap.innerHTML = `
      <div class="vsp-runs-v3-toolbar">
        <div class="vsp-runs-v3-bar">
          <div class="vsp-runs-v3-left">
            <span class="vsp-runs-v3-chip" data-k="ALL" data-on="1">ALL</span>
            <span class="vsp-runs-v3-chip" data-k="OK" data-on="0">OK</span>
            <span class="vsp-runs-v3-chip" data-k="WARN" data-on="0">WARN</span>
            <span class="vsp-runs-v3-chip" data-k="FAIL" data-on="0">FAIL</span>
            <span class="vsp-runs-v3-chip" data-k="UNKNOWN" data-on="0">UNKNOWN</span>
            <input class="vsp-runs-v3-input" id="vsp_runs_v3_q" placeholder="Search RID / status / anything..." />
          </div>
          <div class="vsp-runs-v3-right">
            <select class="vsp-runs-v3-sel" id="vsp_runs_v3_sort">
              <option value="date_desc">Date ↓ (newest)</option>
              <option value="date_asc">Date ↑ (oldest)</option>
              <option value="rid_desc">RID ↓</option>
              <option value="rid_asc">RID ↑</option>
            </select>
            <span class="vsp-runs-v3-muted" id="vsp_runs_v3_count">...</span>
            <button class="vsp-runs-v3-btn" id="vsp_runs_v3_reload">Reload</button>
          </div>
        </div>
      </div>

      <div class="vsp-runs-v3-tablewrap">
        <table class="vsp-runs-v3-table" id="vsp_runs_v3_table">
          <thead>
            <tr>
              <th style="width:32%">RID</th>
              <th style="width:12%">STATUS</th>
              <th style="width:20%">DATE</th>
              <th style="width:36%">ACTIONS</th>
            </tr>
          </thead>
          <tbody id="vsp_runs_v3_tbody">
            <tr><td colspan="4" class="vsp-runs-v3-muted">Loading…</td></tr>
          </tbody>
        </table>
      </div>
    `;

    if(ins.before) ins.parent.insertBefore(wrap, ins.before);
    else ins.parent.appendChild(wrap);

    // events
    const chips = qsa(".vsp-runs-v3-chip", wrap);
    chips.forEach(ch => {
      ch.addEventListener("click", () => {
        const k = ch.getAttribute("data-k");
        if(k === "ALL"){
          chips.forEach(x => x.setAttribute("data-on", x.getAttribute("data-k")==="ALL" ? "1":"0"));
        }else{
          qs('.vsp-runs-v3-chip[data-k="ALL"]', wrap).setAttribute("data-on","0");
          const cur = ch.getAttribute("data-on")==="1";
          ch.setAttribute("data-on", cur ? "0":"1");
        }
        renderLast();
      });
    });

    qs("#vsp_runs_v3_q", wrap).addEventListener("input", () => renderLast());
    qs("#vsp_runs_v3_sort", wrap).addEventListener("change", () => renderLast());
    qs("#vsp_runs_v3_reload", wrap).addEventListener("click", () => load());
  }

  let LAST_ITEMS = [];

  function applyFilters(items){
    const wrap = qs("#vsp_runs_v3_wrap");
    if(!wrap) return items;
    const q = (qs("#vsp_runs_v3_q", wrap).value||"").trim().toLowerCase();
    const chips = qsa(".vsp-runs-v3-chip", wrap).filter(x => x.getAttribute("data-on")==="1").map(x => x.getAttribute("data-k"));
    const active = chips.length ? chips : ["ALL"];

    let out = items.slice();

    if(active.indexOf("ALL")<0){
      out = out.filter(it => active.indexOf(it._status)>=0);
    }
    if(q){
      out = out.filter(it => (it._rid + " " + it._status + " " + it._date + " " + it._raw).toLowerCase().indexOf(q) >= 0);
    }

    const sort = qs("#vsp_runs_v3_sort", wrap).value;
    out.sort((a,b)=>{
      if(sort==="date_asc") return (a._date||"").localeCompare(b._date||"");
      if(sort==="rid_desc") return (b._rid||"").localeCompare(a._rid||"");
      if(sort==="rid_asc")  return (a._rid||"").localeCompare(b._rid||"");
      return (b._date||"").localeCompare(a._date||""); // date_desc
    });

    return out;
  }

  function render(items){
    LAST_ITEMS = items || LAST_ITEMS || [];
    const wrap = qs("#vsp_runs_v3_wrap");
    if(!wrap) return;
    const tbody = qs("#vsp_runs_v3_tbody", wrap);
    const count = qs("#vsp_runs_v3_count", wrap);

    const vis = applyFilters(LAST_ITEMS);
    count.textContent = `total=${LAST_ITEMS.length} shown=${vis.length}`;

    if(!vis.length){
      tbody.innerHTML = `<tr><td colspan="4" class="vsp-runs-v3-muted">No runs match filters.</td></tr>`;
      return;
    }

    tbody.innerHTML = "";
    for(const it of vis){
      const tr = document.createElement("tr");
      const dash = document.createElement("a");
      dash.className = "vsp-runs-v3-mini";
      dash.textContent = "Dashboard";
      dash.href = "/c/dashboard?rid="+encodeURIComponent(it._rid);
      dash.addEventListener("click", (e)=>{ try{ setRid(it._rid); }catch(_e){} });

      const use = document.createElement("span");
      use.className = "vsp-runs-v3-mini";
      use.textContent = "Use RID";
      use.addEventListener("click", ()=>{ setRid(it._rid); location.reload(); });

      const csv = document.createElement("a");
      csv.className = "vsp-runs-v3-mini";
      csv.textContent = "CSV";
      csv.href = "/api/vsp/export_csv?rid="+encodeURIComponent(it._rid);

      const sum = document.createElement("a");
      sum.className = "vsp-runs-v3-mini";
      sum.textContent = "Summary";
      sum.href = "/api/vsp/run_file_allow?rid="+encodeURIComponent(it._rid)+"&path="+encodeURIComponent("reports/run_gate_summary.json");

      const act = document.createElement("div");
      act.className = "vsp-runs-v3-actions";
      act.appendChild(use);
      act.appendChild(dash);
      act.appendChild(csv);
      act.appendChild(sum);

      tr.innerHTML = `
        <td><div style="font-weight:600">${it._rid||""}</div></td>
        <td>${it._status||"UNKNOWN"}</td>
        <td class="vsp-runs-v3-muted">${it._date||""}</td>
        <td></td>
      `;
      tr.children[3].appendChild(act);
      tbody.appendChild(tr);
    }
  }

  function renderLast(){ try{ render(LAST_ITEMS); }catch(e){ log("render err", e); } }

  async function load(){
    buildFrame();
    const wrap = qs("#vsp_runs_v3_wrap");
    if(!wrap) return;

    const tbody = qs("#vsp_runs_v3_tbody", wrap);
    tbody.innerHTML = `<tr><td colspan="4" class="vsp-runs-v3-muted">Loading…</td></tr>`;

    try{
      const r = await fetch(API, { credentials: "same-origin" });
      const j = await r.json();
      const items = (j && (j.items || j.data || j.runs || [])) || [];
      const norm = [];
      for(const x of items){
        const rid = String(pick(x, ["rid","RID","run_id","id"], "")||"");
        if(!rid) continue;
        const st = normStatus(pick(x, ["status","overall","verdict","gate","result"], "UNKNOWN"));
        const dt = pickDate(x);
        norm.push({
          _rid: rid,
          _status: st,
          _date: dt,
          _raw: JSON.stringify(x).slice(0,4000)
        });
      }
      log("runs fetched", "items=", items.length, "norm=", norm.length);
      render(norm);
      hideLegacyRunsList(); // keep legacy hidden after render
    }catch(e){
      log("load err", e);
      tbody.innerHTML = `<tr><td colspan="4" class="vsp-runs-v3-muted">Failed to load runs. Check console/network.</td></tr>`;
    }
  }

  function boot(){
    try{
      if(location.pathname.indexOf("/c/runs")<0 && location.pathname.indexOf("/runs")<0) return;
      buildFrame();
      load();
      log("runs list v3 ready");
    }catch(e){ log("boot err", e); }
  }

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
""".replace("{MARK}", MARK)

# append safely
s2 = s.rstrip() + "\n\n" + js + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended P482f block into vsp_c_runs_v1.js")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 3; }
else
  echo "[WARN] node not found; skip syntax check" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || sudo systemctl restart "$SVC"
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P482f done. Close tab /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
