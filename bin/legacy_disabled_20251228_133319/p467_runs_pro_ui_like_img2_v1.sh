#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P467_RUNS_PRO_UI_V1"
if MARK in s:
    print("[OK] already patched P467")
    raise SystemExit(0)

addon = r'''
/* --- VSP_P467_RUNS_PRO_UI_V1 --- */
(function(){
  if (window.__VSP_P467_ON) return;
  window.__VSP_P467_ON = true;

  const LS = {
    q: "vsp_runspro_q_v1",
    overall: "vsp_runspro_overall_v1",
    degraded: "vsp_runspro_degraded_v1",
    from: "vsp_runspro_from_v1",
    to: "vsp_runspro_to_v1",
    ps: "vsp_runspro_ps_v1",
    page: "vsp_runspro_page_v1",
  };

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function t(el){ return (el && el.textContent ? el.textContent : "").trim(); }
  function esc(s){ return String(s||"").replace(/[&<>"']/g, m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m])); }

  function lsGet(k, d=""){ try{ const v=localStorage.getItem(k); return (v==null?d:v); }catch(e){ return d; } }
  function lsSet(k, v){ try{ localStorage.setItem(k, String(v)); }catch(e){} }

  function ensureCss(){
    if (qs("#vsp_p467_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p467_css";
    st.textContent = `
      .vsp-p467-wrap{ margin-top:10px; }
      .vsp-p467-top{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-badges{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-badge{ padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467-toolbar{ margin-top:10px; display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467-inp,.vsp-p467-sel,.vsp-p467-date,.vsp-p467-btn{
        padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12);
        background: rgba(0,0,0,.25); color:#fff;
      }
      .vsp-p467-inp{ min-width:220px; }
      .vsp-p467-btn{ cursor:pointer; }
      .vsp-p467-btn:hover{ border-color: rgba(255,255,255,.22); }
      .vsp-p467-table{ margin-top:10px; width:100%; border-collapse:separate; border-spacing:0 10px; }
      .vsp-p467-row{ background: rgba(0,0,0,.18); border:1px solid rgba(255,255,255,.08); border-radius:14px; }
      .vsp-p467-td{ padding:10px 12px; vertical-align:middle; }
      .vsp-p467-rid{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size:12px; }
      .vsp-p467-pill{ display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467-actions{ display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
      .vsp-p467-small{ font-size:12px; opacity:.75; }
      .vsp-p467-hide-legacy{ display:none !important; }
      .vsp-p467-page{ display:flex; gap:8px; align-items:center; }
    `;
    document.head.appendChild(st);
  }

  function findRunsRoot(){
    // ưu tiên khu vực có placeholder "Filter by RID / label / date (client-side)" như ảnh 1
    const inp = qsa("input").find(i => (i.getAttribute("placeholder")||"").toLowerCase().includes("filter by rid"));
    return (inp && (inp.closest("section")||inp.closest(".card")||inp.closest("div"))) || qs("#vsp-dashboard-main") || document.body;
  }

  function hideLegacyList(root){
    // Hide the legacy list/table area: the block right under the Filter input
    const inp = qsa("input", root).find(i => (i.getAttribute("placeholder")||"").toLowerCase().includes("filter by rid"));
    if (!inp) return;
    // attempt to hide its following list container (siblings)
    const host = inp.closest("div") || inp.parentElement || root;
    // hide anything that contains repeated "Use RID" buttons (legacy rendering)
    const cand = qsa("*", root).filter(el=>{
      const txt = t(el).toLowerCase();
      return txt.includes("use rid") && txt.includes("reports.tgz") && txt.includes("dashboard") && txt.includes("csv");
    });
    // hide the parents of these elements to stop duplication view
    for(const el of cand){
      const box = el.closest("table") || el.closest("div");
      if (box) box.classList.add("vsp-p467-hide-legacy");
    }
    // also hide the filter input row itself (we will provide our own)
    // but keep it if you want — we keep it visible
    host.classList.remove("vsp-p467-hide-legacy");
  }

  function mount(root){
    let m = qs("#vsp_runs_pro_mount", root);
    if (m) return m;
    m = document.createElement("div");
    m.id = "vsp_runs_pro_mount";
    m.className = "vsp-p467-wrap";
    // place near the start of Runs & Reports section
    const h2 = qsa("h2", root).find(x => t(x).toLowerCase().includes("runs"));
    if (h2 && h2.parentElement) h2.parentElement.insertBefore(m, h2.nextSibling);
    else root.insertBefore(m, root.firstChild);
    return m;
  }

  async function apiRuns(limit){
    const url = "/api/vsp/runs?limit="+encodeURIComponent(limit)+"&include_ci=1";
    const r = await fetch(url, {credentials:"same-origin"});
    const j = await r.json().catch(()=>null);
    if (!r.ok) throw new Error("HTTP "+r.status);
    return j;
  }

  function pickItems(j){
    if (!j) return [];
    if (Array.isArray(j)) return j;
    if (Array.isArray(j.items)) return j.items;
    if (Array.isArray(j.runs)) return j.runs;
    if (Array.isArray(j.data)) return j.data;
    return [];
  }

  function normOverall(x){
    const v = String(x||"UNKNOWN").toUpperCase();
    if (["GREEN","AMBER","RED","UNKNOWN"].includes(v)) return v;
    if (["PASS","OK"].includes(v)) return "GREEN";
    if (["FAIL","BLOCK"].includes(v)) return "RED";
    return "UNKNOWN";
  }

  function getRid(it){
    return (it && (it.rid || it.RID || it.id || it.run_id)) ? String(it.rid||it.RID||it.id||it.run_id) : "";
  }

  function getEpoch(it){
    // best effort: ts / time / created / date
    const cand = it && (it.ts || it.time || it.created || it.date || it.label_ts || it.label);
    if (typeof cand === "number") return cand>1e12?cand:cand*1000;
    if (typeof cand === "string"){
      // try ISO
      const d = new Date(cand);
      if (!isNaN(d.getTime())) return d.getTime();
      // try "YYYY-MM-DD HH:MM"
      const m = cand.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
      if (m){
        const dt = new Date(+m[1], +m[2]-1, +m[3], +m[4], +m[5], 0, 0);
        return dt.getTime()||0;
      }
    }
    return 0;
  }

  function getOverall(it){
    return normOverall(it && (it.overall || it.status || (it.gate && it.gate.overall) || (it.run_gate && it.run_gate.overall)));
  }

  function isDegraded(it){
    const v = it && (it.degraded || it.is_degraded || (it.gate && it.gate.degraded) || (it.run_gate && it.run_gate.degraded));
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v > 0;
    const s = String(v||"").toLowerCase();
    if (["true","1","yes","ok"].includes(s)) return true;
    return false;
  }

  function fmtTime(ms){
    if(!ms) return "-";
    const d=new Date(ms);
    const pad=n=>String(n).padStart(2,"0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  function withinDate(ms, from, to){
    if (!ms) return true;
    const d = new Date(ms);
    const ymd = d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate();
    if (from){
      const f = from.replaceAll("-","");
      if (ymd < +f) return false;
    }
    if (to){
      const tt = to.replaceAll("-","");
      if (ymd > +tt) return false;
    }
    return true;
  }

  function dedupe(items){
    const seen = new Set();
    const out = [];
    for(const it of items){
      const rid = getRid(it);
      const ep = getEpoch(it);
      const key = rid + "|" + String(ep||0);
      if (!rid) continue;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(it);
    }
    return out;
  }

  function buildUrl(path, rid){
    const u = new URL(path, location.origin);
    if (rid) u.searchParams.set("rid", rid);
    return u.toString();
  }

  function openJson(rid){
    // best effort: users already use run_file_allow; keep it compatible
    const u1 = buildUrl("/api/vsp/run_file_allow?path=findings_unified.json&limit=200", rid);
    window.open(u1, "_blank");
  }

  function openHtml(rid){
    // open some known html report file if allowed by backend; fallback to /runs itself
    const u = buildUrl("/api/vsp/run_file_allow?path=reports/findings_unified.html&limit=200", rid);
    window.open(u, "_blank");
  }

  async function render(){
    const root = findRunsRoot();
    ensureCss();
    hideLegacyList(root);
    const m = mount(root);

    // state
    const q = lsGet(LS.q,"");
    const overall = lsGet(LS.overall,"ALL");
    const degraded = lsGet(LS.degraded,"ALL");
    const from = lsGet(LS.from,"");
    const to = lsGet(LS.to,"");
    const ps = parseInt(lsGet(LS.ps,"20"),10) || 20;
    const page = parseInt(lsGet(LS.page,"1"),10) || 1;

    m.innerHTML = `
      <div class="vsp-p467-top">
        <div class="vsp-p467-small">Runs & Reports Quick Actions (commercial)</div>
        <div class="vsp-p467-badges" id="vsp_p467_badges"></div>
      </div>

      <div class="vsp-p467-toolbar">
        <input class="vsp-p467-inp" id="vsp_p467_q" placeholder="Search RID..." value="${esc(q)}"/>
        <select class="vsp-p467-sel" id="vsp_p467_overall">
          <option value="ALL">Overall: ALL</option>
          <option value="GREEN">GREEN</option>
          <option value="AMBER">AMBER</option>
          <option value="RED">RED</option>
          <option value="UNKNOWN">UNKNOWN</option>
        </select>
        <select class="vsp-p467-sel" id="vsp_p467_degraded">
          <option value="ALL">Degraded: ALL</option>
          <option value="0">Degraded: 0</option>
          <option value="1">Degraded: 1</option>
        </select>
        <span class="vsp-p467-small">From</span>
        <input class="vsp-p467-date" id="vsp_p467_from" type="date" value="${esc(from)}"/>
        <span class="vsp-p467-small">To</span>
        <input class="vsp-p467-date" id="vsp_p467_to" type="date" value="${esc(to)}"/>
        <button class="vsp-p467-btn" id="vsp_p467_refresh">Refresh</button>
        <button class="vsp-p467-btn" id="vsp_p467_exports">Open Exports</button>
        <button class="vsp-p467-btn" id="vsp_p467_clear">Clear</button>
      </div>

      <div class="vsp-p467-toolbar vsp-p467-page">
        <span class="vsp-p467-small">Page size</span>
        <select class="vsp-p467-sel" id="vsp_p467_ps">
          <option value="10">10/page</option>
          <option value="20">20/page</option>
          <option value="50">50/page</option>
          <option value="100">100/page</option>
          <option value="200">200/page</option>
        </select>
        <button class="vsp-p467-btn" id="vsp_p467_prev">Prev</button>
        <button class="vsp-p467-btn" id="vsp_p467_next">Next</button>
        <span class="vsp-p467-small" id="vsp_p467_pageinfo"></span>
      </div>

      <table class="vsp-p467-table" id="vsp_p467_table"></table>
    `;

    // set defaults
    qs("#vsp_p467_overall", m).value = overall;
    qs("#vsp_p467_degraded", m).value = degraded;
    qs("#vsp_p467_ps", m).value = String(ps);

    function saveState(){
      lsSet(LS.q, qs("#vsp_p467_q", m).value||"");
      lsSet(LS.overall, qs("#vsp_p467_overall", m).value||"ALL");
      lsSet(LS.degraded, qs("#vsp_p467_degraded", m).value||"ALL");
      lsSet(LS.from, qs("#vsp_p467_from", m).value||"");
      lsSet(LS.to, qs("#vsp_p467_to", m).value||"");
      lsSet(LS.ps, qs("#vsp_p467_ps", m).value||"20");
    }

    function setPage(n){ lsSet(LS.page, String(n)); }

    async function loadAndPaint(){
      saveState();
      const limit = 500; // load enough; paginate client-side
      let j=null, items=[];
      try{
        j = await apiRuns(limit);
        items = pickItems(j);
      }catch(e){
        items = [];
      }

      items = dedupe(items).map(it=>{
        return Object.assign({}, it, {
          __rid: getRid(it),
          __ms: getEpoch(it),
          __overall: getOverall(it),
          __degraded: isDegraded(it) ? 1 : 0
        });
      });

      // counts
      const counts = {TOTAL: items.length, GREEN:0, AMBER:0, RED:0, UNKNOWN:0, DEGRADED:0};
      for(const it of items){
        counts[it.__overall] = (counts[it.__overall]||0) + 1;
        if (it.__degraded) counts.DEGRADED += 1;
      }

      const badges = qs("#vsp_p467_badges", m);
      badges.innerHTML = `
        <span class="vsp-p467-badge">Total ${counts.TOTAL}</span>
        <span class="vsp-p467-badge">GREEN ${counts.GREEN}</span>
        <span class="vsp-p467-badge">AMBER ${counts.AMBER}</span>
        <span class="vsp-p467-badge">RED ${counts.RED}</span>
        <span class="vsp-p467-badge">UNKNOWN ${counts.UNKNOWN}</span>
        <span class="vsp-p467-badge">DEGRADED ${counts.DEGRADED}</span>
      `;

      // filters
      const qv = (qs("#vsp_p467_q", m).value||"").trim().toLowerCase();
      const ov = qs("#vsp_p467_overall", m).value||"ALL";
      const dv = qs("#vsp_p467_degraded", m).value||"ALL";
      const fv = qs("#vsp_p467_from", m).value||"";
      const tv = qs("#vsp_p467_to", m).value||"";

      let filtered = items.filter(it=>{
        if (qv && !String(it.__rid||"").toLowerCase().includes(qv)) return false;
        if (ov !== "ALL" && it.__overall !== ov) return false;
        if (dv !== "ALL" && String(it.__degraded) !== dv) return false;
        if (!withinDate(it.__ms, fv, tv)) return false;
        return true;
      });

      // sort newest first
      filtered.sort((a,b)=> (b.__ms||0) - (a.__ms||0));

      const psNow = parseInt(qs("#vsp_p467_ps", m).value||"20",10) || 20;
      let pageNow = parseInt(lsGet(LS.page,"1"),10) || 1;
      const maxPage = Math.max(1, Math.ceil(filtered.length / psNow));
      if (pageNow > maxPage) pageNow = maxPage;
      if (pageNow < 1) pageNow = 1;
      setPage(pageNow);

      const start = (pageNow-1)*psNow;
      const chunk = filtered.slice(start, start+psNow);

      qs("#vsp_p467_pageinfo", m).textContent = `Showing ${chunk.length}/${filtered.length} (page ${pageNow}/${maxPage})`;

      // table
      const tb = qs("#vsp_p467_table", m);
      tb.innerHTML = `
        <tr class="vsp-p467-row">
          <td class="vsp-p467-td vsp-p467-small">RID</td>
          <td class="vsp-p467-td vsp-p467-small">DATE</td>
          <td class="vsp-p467-td vsp-p467-small">OVERALL</td>
          <td class="vsp-p467-td vsp-p467-small">DEGRADED</td>
          <td class="vsp-p467-td vsp-p467-small" style="text-align:right;">ACTIONS</td>
        </tr>
      `;

      for(const it of chunk){
        const rid = it.__rid;
        const date = fmtTime(it.__ms);
        const overallPill = `<span class="vsp-p467-pill">${esc(it.__overall)}</span>`;
        const degrPill = `<span class="vsp-p467-pill">${it.__degraded? "OK":"-"}</span>`;

        const csv = buildUrl("/api/vsp/export_csv", rid);
        const tgz = buildUrl("/api/vsp/export_tgz", rid);

        const row = document.createElement("tr");
        row.className="vsp-p467-row";
        row.innerHTML = `
          <td class="vsp-p467-td vsp-p467-rid">
            <div>${esc(rid)}</div>
            <div class="vsp-p467-small">
              <button class="vsp-p467-btn" data-act="copy" data-rid="${esc(rid)}">Copy RID</button>
              <button class="vsp-p467-btn" data-act="use" data-rid="${esc(rid)}">Use RID</button>
            </div>
          </td>
          <td class="vsp-p467-td"><span class="vsp-p467-pill">${esc(date)}</span></td>
          <td class="vsp-p467-td">${overallPill}</td>
          <td class="vsp-p467-td">${degrPill}</td>
          <td class="vsp-p467-td">
            <div class="vsp-p467-actions">
              <a class="vsp-p467-btn" href="${esc(csv)}">CSV</a>
              <a class="vsp-p467-btn" href="${esc(tgz)}">TGZ</a>
              <button class="vsp-p467-btn" data-act="json" data-rid="${esc(rid)}">Open JSON</button>
              <button class="vsp-p467-btn" data-act="html" data-rid="${esc(rid)}">Open HTML</button>
            </div>
          </td>
        `;
        tb.appendChild(row);
      }

      // bind actions
      tb.addEventListener("click", (ev)=>{
        const btn = ev.target && ev.target.closest ? ev.target.closest("button") : null;
        if(!btn) return;
        const act = btn.getAttribute("data-act")||"";
        const rid = btn.getAttribute("data-rid")||"";
        if(!rid) return;

        if(act==="copy"){
          try{ navigator.clipboard.writeText(rid); }catch(e){}
        }else if(act==="use"){
          // keep behavior: set URL rid param and reload same /c/runs
          const u = new URL(location.href);
          u.searchParams.set("rid", rid);
          location.href = u.toString();
        }else if(act==="json"){
          openJson(rid);
        }else if(act==="html"){
          openHtml(rid);
        }
      }, {once:true});
    }

    // buttons
    qs("#vsp_p467_refresh", m).addEventListener("click", ()=>loadAndPaint());
    qs("#vsp_p467_exports", m).addEventListener("click", ()=>window.open("/api/vsp/exports_v1","_blank"));
    qs("#vsp_p467_clear", m).addEventListener("click", ()=>{
      qs("#vsp_p467_q", m).value="";
      qs("#vsp_p467_overall", m).value="ALL";
      qs("#vsp_p467_degraded", m).value="ALL";
      qs("#vsp_p467_from", m).value="";
      qs("#vsp_p467_to", m).value="";
      qs("#vsp_p467_ps", m).value="20";
      setPage(1);
      loadAndPaint();
    });
    qs("#vsp_p467_prev", m).addEventListener("click", ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(Math.max(1, cur-1));
      loadAndPaint();
    });
    qs("#vsp_p467_next", m).addEventListener("click", ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(cur+1);
      loadAndPaint();
    });

    // change events -> reload
    qsa("#vsp_p467_q,#vsp_p467_overall,#vsp_p467_degraded,#vsp_p467_from,#vsp_p467_to,#vsp_p467_ps", m).forEach(el=>{
      el.addEventListener("change", ()=>{ setPage(1); loadAndPaint(); });
      if (el.id==="vsp_p467_q") el.addEventListener("input", ()=>{ setPage(1); loadAndPaint(); });
    });

    // first paint
    loadAndPaint();
  }

  function boot(){
    const root = findRunsRoot();
    ensureCss();
    hideLegacyList(root);
    render().catch(()=>{});
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
  setTimeout(boot, 900); // guard for late render
})();
 /* --- /VSP_P467_RUNS_PRO_UI_V1 --- */
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P467 RunsPro UI addon")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P467 done. Hard refresh /c/runs (Ctrl+Shift+R). Legacy list should hide; Runs Pro UI should appear like image#2." | tee -a "$OUT/log.txt"
