#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need sed; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove older injected blocks that caused double-UI / runtime errors
BLOCK_MARKERS = [
  "VSP_P467_RUNS_PRO_UI_LIKE_IMG2_V1",
  "VSP_P467B_RUNS_PRO_FOR_C_RUNS_V1",
  "VSP_P467C_RUNS_PRO_CLEAN_V1",
  "VSP_P467D_C_RUNS_PRO_FINAL_V1",  # in case re-run
]
for m in BLOCK_MARKERS:
    s2 = re.sub(r";?/\*\s*====================\s*"+re.escape(m)+r"\s*====================\s*\*/.*?/\*\s*====================\s*/"+re.escape(m)+r"\s*====================\s*\*/\s*;?",
                "\n", s, flags=re.S|re.M)
    s = s2

addon = r"""
;/* ===================== VSP_P467D_C_RUNS_PRO_FINAL_V1 ===================== */
(function(){
  try{
    if(window.__VSP_P467D_C_RUNS_PRO_FINAL_V1) return;
    window.__VSP_P467D_C_RUNS_PRO_FINAL_V1 = true;

    const log = (...a)=>{ try{ console.log("[P467D]", ...a); }catch(e){} };
    const warn = (...a)=>{ try{ console.warn("[P467D]", ...a); }catch(e){} };

    const qs = (k)=>{ try{ return new URLSearchParams(location.search||"").get(k); }catch(e){ return null; } };
    const setQs = (k,v)=>{
      try{
        const u = new URL(location.href);
        if(v==null || v==="") u.searchParams.delete(k); else u.searchParams.set(k,String(v));
        history.replaceState(null,"",u.toString());
      }catch(e){}
    };

    const dashRoot = ()=>{
      try{
        if(window.__VSP_DASH_ROOT) return window.__VSP_DASH_ROOT();
      }catch(e){}
      return document.body;
    };

    // ---- safe legacy hide (must NOT depend on old addons) ----
    function safeHideLegacy(proRoot){
      let hidden = 0;
      const isInsidePro = (el)=>{ try{ return !!(proRoot && el && el.closest && el.closest('[data-vsp-runs-pro="1"]')); }catch(e){ return False; } };

      // hide legacy "Pick a RID / Filter by RID..." card
      const inputs = Array.from(document.querySelectorAll('input,textarea,select'));
      for(const it of inputs){
        if(isInsidePro(it)) continue;
        const ph = (it.getAttribute('placeholder')||"").toLowerCase();
        if(ph.includes('filter by rid') || ph.includes('filter by')){
          let n = it;
          for(let i=0;i<8 && n;i++){
            const t = ((n.innerText||"") + " " + (n.textContent||"")).toLowerCase();
            if(t.includes('label/ts') || t.includes('pick a rid') || t.includes('runs & reports')){
              n.style.display = "none";
              n.setAttribute("data-vsp-hidden-by","p467d");
              hidden++;
              break;
            }
            n = n.parentElement;
          }
        }
      }

      // hide legacy top table (RID/overall/csv/html/sarif/summary/actions)
      const tables = Array.from(document.querySelectorAll('table'));
      for(const tb of tables){
        if(isInsidePro(tb)) continue;
        const th = Array.from(tb.querySelectorAll('th')).map(x=>(x.textContent||"").trim().toLowerCase());
        const sig = ["rid","overall","csv","html","sarif","summary","actions"];
        const hit = sig.filter(x=>th.includes(x)).length >= 5;
        if(hit){
          let n = tb;
          for(let i=0;i<10 && n;i++){
            if(n.tagName && (n.tagName.toLowerCase()==="section" || n.tagName.toLowerCase()==="main" || n.tagName.toLowerCase()==="div")){
              n.style.display = "none";
              n.setAttribute("data-vsp-hidden-by","p467d");
              hidden++;
              break;
            }
            n = n.parentElement;
          }
        }
      }

      // hide any block that explicitly shows the old header strings
      const blocks = Array.from(document.querySelectorAll('section,main,div'));
      for(const b of blocks){
        if(isInsidePro(b)) continue;
        const t = (b.innerText||"").toLowerCase();
        if(t.includes('runs loaded') && t.includes('download reports.tgz') && t.includes('download findings')){
          b.style.display = "none";
          b.setAttribute("data-vsp-hidden-by","p467d");
          hidden++;
        }
      }

      log("legacy blocks hidden:", hidden);
      return hidden;
    }

    // ---- runs API normalization ----
    function normalizeRunsPayload(j){
      if(!j || typeof j!=="object") return null;

      // preferred: /api/vsp/runs
      if(Array.isArray(j.runs) && typeof j.total === "number"){
        const runs = j.runs.map(x=>({
          rid: (x && (x.rid || x.run_id || x.name)) || "",
          mtime: (x && (x.mtime || x.ts || x.time || x.mtime_epoch)) || null,
          raw: x || {}
        })).filter(x=>x.rid);
        return { total: j.total, limit: j.limit||runs.length, offset: j.offset||0, runs };
      }

      // /api/vsp/runs_v3 shape
      if(Array.isArray(j.runs) && (typeof j.total==="number" || typeof j.total==="string")){
        const runs = j.runs.map(x=>({
          rid: (x && (x.rid || x.run_id || x.name)) || "",
          mtime: (x && (x.mtime || x.ts || x.time)) || null,
          raw: x || {}
        })).filter(x=>x.rid);
        const total = (typeof j.total==="number") ? j.total : parseInt(j.total,10) || runs.length;
        return { total, limit: runs.length, offset: 0, runs };
      }

      // /api/ui/runs_v3 items shape
      if(Array.isArray(j.items)){
        const runs = j.items.map(x=>({
          rid: (x && (x.rid || x.run_id || x.name)) || "",
          mtime: (x && (x.mtime || x.ts || x.time)) || null,
          raw: x || {}
        })).filter(x=>x.rid);
        const total = (typeof j.total==="number") ? j.total : runs.length;
        return { total, limit: runs.length, offset: 0, runs };
      }

      return null;
    }

    function fmtDate(mtime){
      try{
        if(mtime == null) return "";
        // mtime may be epoch seconds
        if(typeof mtime === "number"){
          const ms = (mtime > 10_000_000_000 ? mtime : mtime*1000);
          return new Date(ms).toLocaleString();
        }
        // ISO string
        const d = new Date(String(mtime));
        if(!isNaN(d.getTime())) return d.toLocaleString();
      }catch(e){}
      return String(mtime||"");
    }

    function dedupeRuns(runs){
      const m = new Map();
      for(const r of (runs||[])){
        const k = r.rid;
        if(!k) continue;
        const prev = m.get(k);
        if(!prev) m.set(k,r);
        else{
          // keep newest if possible
          const a = prev.mtime, b = r.mtime;
          if(typeof a==="number" && typeof b==="number" && b>a) m.set(k,r);
        }
      }
      return Array.from(m.values());
    }

    // ---- UI ----
    function injectStylesOnce(){
      if(document.getElementById("vsp_p467d_style")) return;
      const st = document.createElement("style");
      st.id = "vsp_p467d_style";
      st.textContent = `
        .vsp-p467d-wrap{max-width:1400px;margin:14px auto 28px auto;padding:0 12px}
        .vsp-p467d-card{background:rgba(9,12,20,.72);border:1px solid rgba(80,90,120,.35);border-radius:14px;box-shadow:0 14px 50px rgba(0,0,0,.35);backdrop-filter:blur(10px);overflow:hidden}
        .vsp-p467d-head{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;border-bottom:1px solid rgba(80,90,120,.25)}
        .vsp-p467d-title{display:flex;align-items:center;gap:10px;font-weight:700}
        .vsp-p467d-dot{width:10px;height:10px;border-radius:999px;background:#2ecc71;box-shadow:0 0 0 3px rgba(46,204,113,.15)}
        .vsp-p467d-sub{font-size:12px;opacity:.75;margin-top:2px}
        .vsp-p467d-kpis{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}
        .vsp-p467d-chip{font-size:12px;padding:4px 10px;border-radius:999px;border:1px solid rgba(120,140,180,.35);background:rgba(255,255,255,.03)}
        .vsp-p467d-toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;padding:10px 14px}
        .vsp-p467d-in{background:rgba(0,0,0,.18);border:1px solid rgba(120,140,180,.28);border-radius:10px;padding:8px 10px;color:inherit;outline:none}
        .vsp-p467d-btn{background:rgba(255,255,255,.06);border:1px solid rgba(120,140,180,.30);border-radius:10px;padding:8px 10px;color:inherit;cursor:pointer}
        .vsp-p467d-btn:hover{background:rgba(255,255,255,.09)}
        .vsp-p467d-table{width:100%;border-collapse:collapse}
        .vsp-p467d-table th,.vsp-p467d-table td{padding:10px 12px;border-top:1px solid rgba(80,90,120,.20);font-size:13px;vertical-align:middle}
        .vsp-p467d-table th{font-size:12px;opacity:.75;text-transform:uppercase;letter-spacing:.08em}
        .vsp-p467d-actions{display:flex;gap:8px;flex-wrap:wrap}
        .vsp-p467d-mini{padding:5px 10px;border-radius:999px;border:1px solid rgba(120,140,180,.30);background:rgba(255,255,255,.04);font-size:12px;cursor:pointer}
        .vsp-p467d-mini:hover{background:rgba(255,255,255,.07)}
        .vsp-p467d-foot{display:flex;gap:10px;justify-content:space-between;align-items:center;padding:10px 14px;border-top:1px solid rgba(80,90,120,.25)}
        .vsp-p467d-muted{opacity:.75;font-size:12px}
        .vsp-p467d-scan{margin-top:14px}
        .vsp-p467d-grid{display:grid;grid-template-columns: 1fr 320px;gap:12px}
        .vsp-p467d-grid2{display:grid;grid-template-columns: 1fr 1fr;gap:12px}
        @media(max-width:1100px){.vsp-p467d-grid{grid-template-columns:1fr}}
      `;
      document.head.appendChild(st);
    }

    function a(href){
      const x=document.createElement("a");
      x.href=href; x.target="_blank"; x.rel="noopener";
      return x;
    }

    function buildUI(){
      injectStylesOnce();
      const wrap = document.createElement("div");
      wrap.className = "vsp-p467d-wrap";
      wrap.setAttribute("data-vsp-runs-pro","1");
      wrap.id = "vsp_p467d_runs_pro_root";

      wrap.innerHTML = `
        <div class="vsp-p467d-card">
          <div class="vsp-p467d-head">
            <div>
              <div class="vsp-p467d-title"><span class="vsp-p467d-dot"></span>Runs & Reports (commercial)</div>
              <div class="vsp-p467d-sub">/c/runs Pro • payload-safe • hide-safe • anti-blank</div>
            </div>
            <div class="vsp-p467d-kpis" id="vsp_p467d_kpis"></div>
          </div>

          <div class="vsp-p467d-toolbar">
            <input class="vsp-p467d-in" id="vsp_p467d_q" placeholder="Search RID..." style="min-width:220px"/>
            <select class="vsp-p467d-in" id="vsp_p467d_pagesize">
              <option value="20">20/page</option>
              <option value="50">50/page</option>
              <option value="100">100/page</option>
            </select>
            <button class="vsp-p467d-btn" id="vsp_p467d_prev">Prev</button>
            <button class="vsp-p467d-btn" id="vsp_p467d_next">Next</button>
            <span class="vsp-p467d-muted" id="vsp_p467d_pageinfo">…</span>
            <button class="vsp-p467d-btn" id="vsp_p467d_refresh">Refresh</button>
            <button class="vsp-p467d-btn" id="vsp_p467d_open_exports">Open Exports</button>
          </div>

          <div style="overflow:auto">
            <table class="vsp-p467d-table">
              <thead>
                <tr>
                  <th style="min-width:320px">RID</th>
                  <th style="min-width:190px">Date</th>
                  <th style="min-width:110px">Overall</th>
                  <th style="min-width:120px">Degraded</th>
                  <th style="min-width:420px">Actions</th>
                </tr>
              </thead>
              <tbody id="vsp_p467d_tbody">
                <tr><td colspan="5" class="vsp-p467d-muted">Loading…</td></tr>
              </tbody>
            </table>
          </div>

          <div class="vsp-p467d-foot">
            <div class="vsp-p467d-muted" id="vsp_p467d_selected">Selected: (none)</div>
            <div class="vsp-p467d-muted" id="vsp_p467d_status">Ready.</div>
          </div>
        </div>

        <div class="vsp-p467d-card vsp-p467d-scan">
          <div class="vsp-p467d-head">
            <div>
              <div class="vsp-p467d-title">Scan / Start Run</div>
              <div class="vsp-p467d-sub">Kick off via <code>/api/vsp/run_v1</code> and poll <code>/api/vsp/run_status_v1</code></div>
            </div>
            <div class="vsp-p467d-kpis">
              <span class="vsp-p467d-chip" id="vsp_p467d_scan_rid">RID: (none)</span>
            </div>
          </div>
          <div class="vsp-p467d-toolbar vsp-p467d-grid">
            <div>
              <div class="vsp-p467d-muted" style="margin-bottom:6px">Target path</div>
              <input class="vsp-p467d-in" id="vsp_p467d_scan_path" style="width:100%" value="/home/test/Data/SECURITY_BUNDLE"/>
              <div class="vsp-p467d-muted" style="margin:10px 0 6px 0">Note</div>
              <input class="vsp-p467d-in" id="vsp_p467d_scan_note" style="width:100%" placeholder="optional note for audit trail"/>
            </div>
            <div>
              <div class="vsp-p467d-muted" style="margin-bottom:6px">Mode</div>
              <select class="vsp-p467d-in" id="vsp_p467d_scan_mode" style="width:100%">
                <option value="FULL">FULL (8 tools)</option>
                <option value="FAST">FAST</option>
              </select>
              <div style="height:10px"></div>
              <button class="vsp-p467d-btn" id="vsp_p467d_scan_start" style="width:100%">Start scan</button>
              <div style="height:8px"></div>
              <button class="vsp-p467d-btn" id="vsp_p467d_scan_poll" style="width:100%">Refresh status</button>
            </div>
          </div>
          <div class="vsp-p467d-toolbar">
            <div class="vsp-p467d-muted" id="vsp_p467d_scan_status">Ready.</div>
          </div>
        </div>
      `;
      return wrap;
    }

    async function fetchJson(url, opt){
      const res = await fetch(url, opt||{});
      const ct = (res.headers.get("content-type")||"").toLowerCase();
      let j = null;
      if(ct.includes("application/json")) j = await res.json().catch(()=>null);
      else j = await res.text().catch(()=>null);
      return { ok: res.ok, status: res.status, j };
    }

    function computeKpis(total){
      // we only know total reliably from /api/vsp/runs; keep others at 0/unknown to avoid lying
      const unknown = (typeof total==="number" ? total : 0);
      return {
        total: unknown,
        green: 0, amber: 0, red: 0,
        unknown,
        degraded: 0,
      };
    }

    function renderKpis(el, k){
      el.innerHTML = `
        <span class="vsp-p467d-chip">Total ${k.total}</span>
        <span class="vsp-p467d-chip">GREEN ${k.green}</span>
        <span class="vsp-p467d-chip">AMBER ${k.amber}</span>
        <span class="vsp-p467d-chip">RED ${k.red}</span>
        <span class="vsp-p467d-chip">UNKNOWN ${k.unknown}</span>
        <span class="vsp-p467d-chip">DEGRADED ${k.degraded}</span>
      `;
    }

    function buildRow(rid, dateStr){
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td style="font-weight:650">${rid}</td>
        <td>${dateStr}</td>
        <td><span class="vsp-p467d-chip">UNKNOWN</span></td>
        <td><span class="vsp-p467d-chip">OK</span></td>
        <td>
          <div class="vsp-p467d-actions">
            <button class="vsp-p467d-mini" data-act="csv">CSV</button>
            <button class="vsp-p467d-mini" data-act="tgz">TGZ</button>
            <button class="vsp-p467d-mini" data-act="open_json">Open JSON</button>
            <button class="vsp-p467d-mini" data-act="open_html">Open HTML</button>
            <button class="vsp-p467d-mini" data-act="use_rid">Use RID</button>
          </div>
        </td>
      `;
      tr.querySelectorAll("button[data-act]").forEach(btn=>{
        btn.addEventListener("click", ()=>{
          const act = btn.getAttribute("data-act");
          const enc = encodeURIComponent(rid);

          if(act==="use_rid"){
            setQs("rid", rid);
            location.href = "/c/runs?rid=" + enc;
            return;
          }
          if(act==="csv"){
            window.open("/api/vsp/export_csv?rid=" + enc, "_blank", "noopener");
            return;
          }
          if(act==="tgz"){
            window.open("/api/vsp/export_tgz?rid=" + enc, "_blank", "noopener");
            return;
          }
          if(act==="open_json"){
            // safest: open allow-list file if supported; else open a generic run json endpoint if exists
            window.open("/api/vsp/run_file_allow?rid=" + enc + "&path=findings_unified.json", "_blank", "noopener");
            return;
          }
          if(act==="open_html"){
            window.open("/api/vsp/run_file_allow?rid=" + enc + "&path=reports/findings_unified.html", "_blank", "noopener");
            return;
          }
        });
      });
      return tr;
    }

    async function runStartAndPoll(path, mode, note, setScanRid, setScanStatus){
      setScanStatus("Starting…");
      const payload = { target_path: path, mode: mode, note: note };
      const started = await fetchJson("/api/vsp/run_v1", {
        method:"POST",
        headers:{ "content-type":"application/json" },
        body: JSON.stringify(payload)
      }).catch(e=>({ok:false,status:0,j:String(e)}));

      if(!started || !started.ok){
        setScanStatus("Start failed: HTTP " + (started && started.status) + " (check backend /api/vsp/run_v1)");
        return;
      }

      const j = started.j || {};
      const rid = j.rid || j.run_id || j.id || "";
      if(!rid){
        setScanStatus("Start ok but no rid returned. Response=" + JSON.stringify(j).slice(0,180));
        return;
      }

      setScanRid(rid);
      setScanStatus("Started RID=" + rid + " … polling");

      // quick poll loop
      for(let i=0;i<20;i++){
        await new Promise(r=>setTimeout(r, 1200));
        const st = await fetchJson("/api/vsp/run_status_v1?rid=" + encodeURIComponent(rid)).catch(e=>({ok:false,status:0,j:String(e)}));
        if(st && st.ok){
          const sj = st.j || {};
          const msg = sj.status || sj.state || sj.msg || JSON.stringify(sj).slice(0,140);
          setScanStatus("Status: " + msg);
          const done = String(sj.done||sj.finished||sj.complete||"").toLowerCase()==="true";
          if(done) break;
        }else{
          setScanStatus("Status poll failed (HTTP " + (st && st.status) + "). Backend may use different contract.");
        }
      }
    }

    async function loadRuns(state, ui){
      ui.status("Loading…");

      const limit = state.pageSize;
      const offset = state.page * limit;

      // prefer /api/vsp/runs (rich + stable)
      let resp = await fetchJson("/api/vsp/runs?limit="+limit+"&offset="+offset).catch(e=>({ok:false,status:0,j:String(e)}));
      let norm = normalizeRunsPayload(resp.j);

      // fallback 1: runs_v3
      if(!norm){
        resp = await fetchJson("/api/vsp/runs_v3?limit="+limit+"&include_ci=1").catch(e=>({ok:false,status:0,j:String(e)}));
        norm = normalizeRunsPayload(resp.j);
      }
      // fallback 2: ui runs_v3
      if(!norm){
        resp = await fetchJson("/api/ui/runs_v3?limit="+limit+"&include_ci=1").catch(e=>({ok:false,status:0,j:String(e)}));
        norm = normalizeRunsPayload(resp.j);
      }

      if(!norm){
        ui.status("Error: bad runs payload (see console). Keeping page non-blank.");
        warn("bad runs payload", resp && resp.j);
        ui.renderRows([]);
        renderKpis(ui.kpisEl, computeKpis(0));
        return;
      }

      // apply search client-side on the page chunk
      let runs = dedupeRuns(norm.runs || []);
      const q = (state.q||"").trim().toLowerCase();
      if(q){
        runs = runs.filter(x=>x.rid.toLowerCase().includes(q));
      }

      renderKpis(ui.kpisEl, computeKpis(norm.total));
      ui.pageInfo(`Showing ${runs.length} (page ${state.page+1}) • total ${norm.total}`);
      ui.renderRows(runs);
      ui.status("Ready.");

      // ensure legacy hidden AFTER our UI exists (avoid blank)
      safeHideLegacy(ui.proRoot);
    }

    function mount(){
      // mount only on /c/runs
      try{
        if(!location.pathname.startsWith("/c/runs")) return;
      }catch(e){}

      const root = dashRoot();
      const pro = buildUI();
      root.prepend(pro);

      const ui = {
        proRoot: pro,
        kpisEl: pro.querySelector("#vsp_p467d_kpis"),
        tbody: pro.querySelector("#vsp_p467d_tbody"),
        q: pro.querySelector("#vsp_p467d_q"),
        pageSize: pro.querySelector("#vsp_p467d_pagesize"),
        prev: pro.querySelector("#vsp_p467d_prev"),
        next: pro.querySelector("#vsp_p467d_next"),
        refresh: pro.querySelector("#vsp_p467d_refresh"),
        openExports: pro.querySelector("#vsp_p467d_open_exports"),
        pageinfo: pro.querySelector("#vsp_p467d_pageinfo"),
        selected: pro.querySelector("#vsp_p467d_selected"),
        statusEl: pro.querySelector("#vsp_p467d_status"),
        scanRid: pro.querySelector("#vsp_p467d_scan_rid"),
        scanStatus: pro.querySelector("#vsp_p467d_scan_status"),
        scanPath: pro.querySelector("#vsp_p467d_scan_path"),
        scanMode: pro.querySelector("#vsp_p467d_scan_mode"),
        scanNote: pro.querySelector("#vsp_p467d_scan_note"),
        scanStart: pro.querySelector("#vsp_p467d_scan_start"),
        scanPoll: pro.querySelector("#vsp_p467d_scan_poll"),
        status(msg){ this.statusEl.textContent = msg; },
        pageInfo(msg){ this.pageinfo.textContent = msg; },
        setSelected(rid){ this.selected.textContent = "Selected: " + (rid||"(none)"); },
        renderRows(runs){
          this.tbody.innerHTML = "";
          if(!runs || !runs.length){
            const tr = document.createElement("tr");
            tr.innerHTML = `<td colspan="5" class="vsp-p467d-muted">No runs found.</td>`;
            this.tbody.appendChild(tr);
            return;
          }
          for(const r of runs){
            const rid = r.rid;
            const tr = buildRow(rid, fmtDate(r.mtime));
            // update selected if URL contains rid
            tr.addEventListener("click", (ev)=>{
              const btn = ev.target && ev.target.closest && ev.target.closest("button");
              if(btn) return;
              this.setSelected(rid);
            });
            this.tbody.appendChild(tr);
          }
        }
      };

      const state = { page: 0, pageSize: 20, q: "" };

      const rid0 = qs("rid") || "";
      if(rid0) ui.setSelected(rid0);

      ui.q.addEventListener("input", ()=>{
        state.q = ui.q.value || "";
        state.page = 0;
        loadRuns(state, ui);
      });
      ui.pageSize.addEventListener("change", ()=>{
        state.pageSize = parseInt(ui.pageSize.value,10) || 20;
        state.page = 0;
        loadRuns(state, ui);
      });
      ui.prev.addEventListener("click", ()=>{
        state.page = Math.max(0, state.page-1);
        loadRuns(state, ui);
      });
      ui.next.addEventListener("click", ()=>{
        state.page = state.page+1;
        loadRuns(state, ui);
      });
      ui.refresh.addEventListener("click", ()=>loadRuns(state, ui));
      ui.openExports.addEventListener("click", ()=>{
        const rid = qs("rid") || rid0 || "";
        if(rid) window.open("/c/runs?rid="+encodeURIComponent(rid), "_blank", "noopener");
        else window.open("/runs", "_blank", "noopener");
      });

      // Scan UI
      function setScanRid(rid){
        ui.scanRid.textContent = "RID: " + rid;
        setQs("rid", rid);
      }
      function setScanStatus(msg){
        ui.scanStatus.textContent = msg;
      }
      ui.scanStart.addEventListener("click", ()=>{
        const path = ui.scanPath.value || "";
        const mode = ui.scanMode.value || "FULL";
        const note = ui.scanNote.value || "";
        runStartAndPoll(path, mode, note, setScanRid, setScanStatus);
      });
      ui.scanPoll.addEventListener("click", async ()=>{
        const rid = (qs("rid")||"").trim();
        if(!rid){ setScanStatus("No RID in URL to poll."); return; }
        const st = await fetchJson("/api/vsp/run_status_v1?rid=" + encodeURIComponent(rid)).catch(e=>({ok:false,status:0,j:String(e)}));
        if(st && st.ok){
          const sj = st.j || {};
          const msg = sj.status || sj.state || sj.msg || JSON.stringify(sj).slice(0,160);
          setScanStatus("Status: " + msg);
        }else{
          setScanStatus("Poll failed (HTTP " + (st && st.status) + ").");
        }
      });

      log("Runs Pro mounted for /c/runs");
      loadRuns(state, ui);
    }

    if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", mount);
    else mount();
  }catch(e){
    try{ console.error("[P467D] fatal", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P467D_C_RUNS_PRO_FINAL_V1 ===================== */
"""
s = s.rstrip() + "\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote", p)
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
else
  echo "[WARN] no systemctl/sudo; restart service manually" | tee -a "$OUT/log.txt"
fi

echo "[OK] Verify marker in JS:" | tee -a "$OUT/log.txt"
grep -n "VSP_P467D_C_RUNS_PRO_FINAL_V1" -n "$F" | head -n 3 | tee -a "$OUT/log.txt" || true

echo "[OK] DONE. Hard refresh /c/runs (Ctrl+Shift+R). Legacy UI should be hidden; Runs Pro + Scan UI visible." | tee -a "$OUT/log.txt"
echo "[OK] Log: $OUT/log.txt"
