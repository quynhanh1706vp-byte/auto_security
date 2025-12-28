#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

F="static/js/vsp_c_runs_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P467C_FIX_MOUNT_HIDE_LEGACY_V1"
if MARK in s:
    print("[OK] already patched P467c")
    raise SystemExit(0)

addon=r"""
/* --- VSP_P467C_FIX_MOUNT_HIDE_LEGACY_V1 --- */
(function(){
  if (window.__VSP_P467C_ON) return;
  window.__VSP_P467C_ON = true;

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && el.textContent ? el.textContent : "").trim(); }
  function esc(s){ return String(s||"").replace(/[&<>"']/g, m=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[m])); }

  function ensureCss(){
    if (qs("#vsp_p467c_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p467c_css";
    st.textContent = `
      .vsp-p467c-hide{ display:none !important; }
      .vsp-p467c-wrap{ margin-top:10px; width:100%; }
      .vsp-p467c-top{ display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467c-badges{ display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
      .vsp-p467c-badge{ padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467c-toolbar{ margin-top:10px; display:flex; gap:10px; flex-wrap:wrap; align-items:center; }
      .vsp-p467c-inp,.vsp-p467c-sel,.vsp-p467c-date,.vsp-p467c-btn{
        padding:8px 10px; border-radius:10px; border:1px solid rgba(255,255,255,.12);
        background: rgba(0,0,0,.25); color:#fff;
      }
      .vsp-p467c-inp{ min-width:240px; }
      .vsp-p467c-btn{ cursor:pointer; }
      .vsp-p467c-btn:hover{ border-color: rgba(255,255,255,.22); }
      .vsp-p467c-table{ margin-top:10px; width:100%; border-collapse:separate; border-spacing:0 10px; }
      .vsp-p467c-row{ background: rgba(0,0,0,.18); border:1px solid rgba(255,255,255,.08); border-radius:14px; }
      .vsp-p467c-td{ padding:10px 12px; vertical-align:middle; }
      .vsp-p467c-rid{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace; font-size:12px; }
      .vsp-p467c-pill{ display:inline-block; padding:2px 8px; border-radius:999px; border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); font-size:12px; }
      .vsp-p467c-actions{ display:flex; gap:8px; flex-wrap:wrap; justify-content:flex-end; }
      .vsp-p467c-small{ font-size:12px; opacity:.75; }
      .vsp-p467c-page{ display:flex; gap:8px; align-items:center; }
    `;
    document.head.appendChild(st);
  }

  function dashRoot(){
    return qs('#vsp-dashboard-main')
      || qs('#vsp_dashboard_main')
      || qs('#vsp-dashboard')
      || document.body;
  }

  function findRunsCard(){
    const dr = dashRoot();
    // ưu tiên input legacy của /c/runs
    const inp = qsa("input", dr).find(i => ((i.getAttribute("placeholder")||"").toLowerCase().includes("filter by rid")));
    if(inp){
      return inp.closest("section") || inp.closest(".card") || inp.closest("div") || dr;
    }
    // fallback: tìm node có text "Runs & Reports"
    const heads = qsa("h1,h2,h3,div,span", dr).filter(el=>{
      const t=txt(el).toLowerCase();
      return t.includes("runs") && t.includes("reports");
    });
    for(const h of heads){
      const box = h.closest("section") || h.closest(".card") || h.closest("div");
      if(box) return box;
    }
    return dr;
  }

  function cleanupBadMounts(){
    // P467b cũ mount nhầm chỗ -> remove
    const bad = qs("#vsp_runs_pro_mount_c") || qs("#vsp_runs_pro_mount_c_runs");
    if(bad && bad.parentElement){
      bad.parentElement.removeChild(bad);
    }
    // hide các block legacy dính chữ "Use RID / Reports.tgz / Dashboard CSV"
    const dr = dashRoot();
    const suspects = qsa("*", dr).filter(el=>{
      const t = txt(el).toLowerCase();
      return t.includes("use rid") && t.includes("reports.tgz") && t.includes("dashboard") && t.includes("csv");
    });
    for(const el of suspects){
      const box = el.closest("table") || el.closest("div");
      if(box) box.classList.add("vsp-p467c-hide");
    }
  }

  function pruneContainer(card, keep){
    // Ẩn TẤT CẢ children legacy trong card để không “trùm dúm”
    Array.from(card.children||[]).forEach(ch=>{
      if(ch===keep) return;
      if(ch.contains && ch.contains(keep)) return;
      ch.classList.add("vsp-p467c-hide");
    });
  }

  async function apiRuns(limit){
    const url = "/api/vsp/runs?limit="+encodeURIComponent(limit)+"&include_ci=1";
    const r = await fetch(url, {credentials:"same-origin"});
    const j = await r.json().catch(()=>null);
    if(!r.ok) throw new Error("HTTP "+r.status);
    return j;
  }

  function pickItems(j){
    if(!j) return [];
    if(Array.isArray(j)) return j;
    if(Array.isArray(j.items)) return j.items;
    if(Array.isArray(j.runs)) return j.runs;
    if(Array.isArray(j.data)) return j.data;
    return [];
  }

  function getRid(it){
    return (it && (it.rid || it.RID || it.id || it.run_id)) ? String(it.rid||it.RID||it.id||it.run_id) : "";
  }
  function getEpoch(it){
    const cand = it && (it.ts || it.time || it.created || it.date || it.label_ts || it.label);
    if (typeof cand === "number") return cand>1e12?cand:cand*1000;
    if (typeof cand === "string"){
      const d = new Date(cand);
      if (!isNaN(d.getTime())) return d.getTime();
      const m = cand.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
      if (m){
        const dt = new Date(+m[1], +m[2]-1, +m[3], +m[4], +m[5], 0, 0);
        return dt.getTime()||0;
      }
    }
    return 0;
  }
  function normOverall(x){
    const v = String(x||"UNKNOWN").toUpperCase();
    if(["GREEN","AMBER","RED","UNKNOWN"].includes(v)) return v;
    if(["PASS","OK"].includes(v)) return "GREEN";
    if(["FAIL","BLOCK"].includes(v)) return "RED";
    return "UNKNOWN";
  }
  function getOverall(it){
    return normOverall(it && (it.overall || it.status || (it.gate && it.gate.overall) || (it.run_gate && it.run_gate.overall)));
  }
  function isDegraded(it){
    const v = it && (it.degraded || it.is_degraded || (it.gate && it.gate.degraded) || (it.run_gate && it.run_gate.degraded));
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v>0;
    const s = String(v||"").toLowerCase();
    return ["true","1","yes","ok"].includes(s);
  }
  function fmtTime(ms){
    if(!ms) return "-";
    const d=new Date(ms);
    const pad=n=>String(n).padStart(2,"0");
    return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }
  function withinDate(ms, from, to){
    if(!ms) return true;
    const d=new Date(ms);
    const ymd = d.getFullYear()*10000 + (d.getMonth()+1)*100 + d.getDate();
    if(from){
      const f=from.replaceAll("-","");
      if(ymd < +f) return false;
    }
    if(to){
      const t=to.replaceAll("-","");
      if(ymd > +t) return false;
    }
    return true;
  }
  function dedupe(items){
    const seen=new Set();
    const out=[];
    for(const it of items){
      const rid=getRid(it);
      const ep=getEpoch(it);
      const key=rid+"|"+String(ep||0);
      if(!rid) continue;
      if(seen.has(key)) continue;
      seen.add(key);
      out.push(it);
    }
    return out;
  }
  function buildUrl(path, rid){
    const u=new URL(path, location.origin);
    if(rid) u.searchParams.set("rid", rid);
    return u.toString();
  }

  const LS = {
    q: "vsp_runspro_q_v1",
    overall: "vsp_runspro_overall_v1",
    degraded: "vsp_runspro_degraded_v1",
    from: "vsp_runspro_from_v1",
    to: "vsp_runspro_to_v1",
    ps: "vsp_runspro_ps_v1",
    page: "vsp_runspro_page_v1",
  };
  function lsGet(k, d=""){ try{ const v=localStorage.getItem(k); return (v==null?d:v); }catch(e){ return d; } }
  function lsSet(k, v){ try{ localStorage.setItem(k, String(v)); }catch(e){} }

  async function renderIntoCard(){
    ensureCss();
    cleanupBadMounts();

    const card = findRunsCard();
    // tạo mount
    let m = qs("#vsp_runs_pro_mount_c_runs", card);
    if(!m){
      m = document.createElement("div");
      m.id = "vsp_runs_pro_mount_c_runs";
      m.className = "vsp-p467c-wrap";
      // prepend vào card trước
      card.insertBefore(m, card.firstChild);
    }
    // ẩn toàn bộ thứ cũ trong card (giữ lại mount)
    pruneContainer(card, m);

    const q = lsGet(LS.q,"");
    const overall = lsGet(LS.overall,"ALL");
    const degraded = lsGet(LS.degraded,"ALL");
    const from = lsGet(LS.from,"");
    const to = lsGet(LS.to,"");
    const ps = parseInt(lsGet(LS.ps,"20"),10) || 20;
    const page = parseInt(lsGet(LS.page,"1"),10) || 1;

    m.innerHTML = `
      <div class="vsp-p467c-top">
        <div class="vsp-p467c-small">Runs & Reports Quick Actions (commercial)</div>
        <div class="vsp-p467c-badges" id="vsp_p467c_badges"></div>
      </div>

      <div class="vsp-p467c-toolbar">
        <input class="vsp-p467c-inp" id="vsp_p467c_q" placeholder="Search RID..." value="${esc(q)}"/>
        <select class="vsp-p467c-sel" id="vsp_p467c_overall">
          <option value="ALL">Overall: ALL</option>
          <option value="GREEN">GREEN</option>
          <option value="AMBER">AMBER</option>
          <option value="RED">RED</option>
          <option value="UNKNOWN">UNKNOWN</option>
        </select>
        <select class="vsp-p467c-sel" id="vsp_p467c_degraded">
          <option value="ALL">Degraded: ALL</option>
          <option value="0">Degraded: 0</option>
          <option value="1">Degraded: 1</option>
        </select>
        <span class="vsp-p467c-small">From</span>
        <input class="vsp-p467c-date" id="vsp_p467c_from" type="date" value="${esc(from)}"/>
        <span class="vsp-p467c-small">To</span>
        <input class="vsp-p467c-date" id="vsp_p467c_to" type="date" value="${esc(to)}"/>
        <button class="vsp-p467c-btn" id="vsp_p467c_refresh">Refresh</button>
        <button class="vsp-p467c-btn" id="vsp_p467c_exports">Open Exports</button>
        <button class="vsp-p467c-btn" id="vsp_p467c_clear">Clear</button>
      </div>

      <div class="vsp-p467c-toolbar vsp-p467c-page">
        <span class="vsp-p467c-small">Page size</span>
        <select class="vsp-p467c-sel" id="vsp_p467c_ps">
          <option value="10">10/page</option>
          <option value="20">20/page</option>
          <option value="50">50/page</option>
          <option value="100">100/page</option>
          <option value="200">200/page</option>
        </select>
        <button class="vsp-p467c-btn" id="vsp_p467c_prev">Prev</button>
        <button class="vsp-p467c-btn" id="vsp_p467c_next">Next</button>
        <span class="vsp-p467c-small" id="vsp_p467c_pageinfo"></span>
      </div>

      <table class="vsp-p467c-table" id="vsp_p467c_table"></table>
    `;

    qs("#vsp_p467c_overall", m).value = overall;
    qs("#vsp_p467c_degraded", m).value = degraded;
    qs("#vsp_p467c_ps", m).value = String(ps);

    function saveState(){
      lsSet(LS.q, qs("#vsp_p467c_q", m).value||"");
      lsSet(LS.overall, qs("#vsp_p467c_overall", m).value||"ALL");
      lsSet(LS.degraded, qs("#vsp_p467c_degraded", m).value||"ALL");
      lsSet(LS.from, qs("#vsp_p467c_from", m).value||"");
      lsSet(LS.to, qs("#vsp_p467c_to", m).value||"");
      lsSet(LS.ps, qs("#vsp_p467c_ps", m).value||"20");
    }
    function setPage(n){ lsSet(LS.page, String(n)); }

    async function loadAndPaint(){
      saveState();
      let items=[];
      try{
        const j = await apiRuns(500);
        items = pickItems(j);
      }catch(e){
        items=[];
      }

      items = dedupe(items).map(it=>Object.assign({}, it, {
        __rid: getRid(it),
        __ms: getEpoch(it),
        __overall: getOverall(it),
        __degraded: isDegraded(it) ? 1 : 0,
      }));

      const counts={TOTAL:items.length, GREEN:0, AMBER:0, RED:0, UNKNOWN:0, DEGRADED:0};
      for(const it of items){
        counts[it.__overall]=(counts[it.__overall]||0)+1;
        if(it.__degraded) counts.DEGRADED += 1;
      }
      qs("#vsp_p467c_badges", m).innerHTML = `
        <span class="vsp-p467c-badge">Total ${counts.TOTAL}</span>
        <span class="vsp-p467c-badge">GREEN ${counts.GREEN}</span>
        <span class="vsp-p467c-badge">AMBER ${counts.AMBER}</span>
        <span class="vsp-p467c-badge">RED ${counts.RED}</span>
        <span class="vsp-p467c-badge">UNKNOWN ${counts.UNKNOWN}</span>
        <span class="vsp-p467c-badge">DEGRADED ${counts.DEGRADED}</span>
      `;

      const qv=(qs("#vsp_p467c_q", m).value||"").trim().toLowerCase();
      const ov=qs("#vsp_p467c_overall", m).value||"ALL";
      const dv=qs("#vsp_p467c_degraded", m).value||"ALL";
      const fv=qs("#vsp_p467c_from", m).value||"";
      const tv=qs("#vsp_p467c_to", m).value||"";

      let filtered = items.filter(it=>{
        if(qv && !String(it.__rid||"").toLowerCase().includes(qv)) return false;
        if(ov!=="ALL" && it.__overall!==ov) return false;
        if(dv!=="ALL" && String(it.__degraded)!==dv) return false;
        if(!withinDate(it.__ms, fv, tv)) return false;
        return true;
      });

      filtered.sort((a,b)=>(b.__ms||0)-(a.__ms||0));

      const psNow=parseInt(qs("#vsp_p467c_ps", m).value||"20",10)||20;
      let pageNow=parseInt(lsGet(LS.page,"1"),10)||1;
      const maxPage=Math.max(1, Math.ceil(filtered.length/psNow));
      if(pageNow>maxPage) pageNow=maxPage;
      if(pageNow<1) pageNow=1;
      setPage(pageNow);

      const start=(pageNow-1)*psNow;
      const chunk=filtered.slice(start, start+psNow);

      qs("#vsp_p467c_pageinfo", m).textContent = `Showing ${chunk.length}/${filtered.length} (page ${pageNow}/${maxPage})`;

      const tb=qs("#vsp_p467c_table", m);
      tb.innerHTML = `
        <tr class="vsp-p467c-row">
          <td class="vsp-p467c-td vsp-p467c-small">RID</td>
          <td class="vsp-p467c-td vsp-p467c-small">DATE</td>
          <td class="vsp-p467c-td vsp-p467c-small">OVERALL</td>
          <td class="vsp-p467c-td vsp-p467c-small">DEGRADED</td>
          <td class="vsp-p467c-td vsp-p467c-small" style="text-align:right;">ACTIONS</td>
        </tr>
      `;

      for(const it of chunk){
        const rid=it.__rid;
        const date=fmtTime(it.__ms);
        const csv=buildUrl("/api/vsp/export_csv", rid);
        const tgz=buildUrl("/api/vsp/export_tgz", rid);
        const json=buildUrl("/api/vsp/run_file_allow?path=findings_unified.json&limit=200", rid);
        const html=buildUrl("/api/vsp/run_file_allow?path=reports/findings_unified.html&limit=200", rid);

        const row=document.createElement("tr");
        row.className="vsp-p467c-row";
        row.innerHTML = `
          <td class="vsp-p467c-td vsp-p467c-rid">
            <div>${esc(rid)}</div>
            <div class="vsp-p467c-small">
              <button class="vsp-p467c-btn" data-act="copy" data-rid="${esc(rid)}">Copy RID</button>
              <button class="vsp-p467c-btn" data-act="use" data-rid="${esc(rid)}">Use RID</button>
            </div>
          </td>
          <td class="vsp-p467c-td"><span class="vsp-p467c-pill">${esc(date)}</span></td>
          <td class="vsp-p467c-td"><span class="vsp-p467c-pill">${esc(it.__overall)}</span></td>
          <td class="vsp-p467c-td"><span class="vsp-p467c-pill">${it.__degraded? "OK":"-"}</span></td>
          <td class="vsp-p467c-td">
            <div class="vsp-p467c-actions">
              <a class="vsp-p467c-btn" href="${esc(csv)}">CSV</a>
              <a class="vsp-p467c-btn" href="${esc(tgz)}">TGZ</a>
              <a class="vsp-p467c-btn" href="${esc(json)}" target="_blank">Open JSON</a>
              <a class="vsp-p467c-btn" href="${esc(html)}" target="_blank">Open HTML</a>
            </div>
          </td>
        `;
        tb.appendChild(row);
      }

      tb.onclick = (ev)=>{
        const btn = ev.target && ev.target.closest ? ev.target.closest("button") : null;
        if(!btn) return;
        const act = btn.getAttribute("data-act")||"";
        const rid = btn.getAttribute("data-rid")||"";
        if(!rid) return;
        if(act==="copy"){
          try{ navigator.clipboard.writeText(rid); }catch(e){}
        }else if(act==="use"){
          const u = new URL(location.href);
          u.searchParams.set("rid", rid);
          location.href = u.toString();
        }
      };
    }

    qs("#vsp_p467c_refresh", m).onclick = ()=>loadAndPaint();
    qs("#vsp_p467c_exports", m).onclick = ()=>window.open("/api/vsp/exports_v1","_blank");
    qs("#vsp_p467c_clear", m).onclick = ()=>{
      qs("#vsp_p467c_q", m).value="";
      qs("#vsp_p467c_overall", m).value="ALL";
      qs("#vsp_p467c_degraded", m).value="ALL";
      qs("#vsp_p467c_from", m).value="";
      qs("#vsp_p467c_to", m).value="";
      qs("#vsp_p467c_ps", m).value="20";
      setPage(1);
      loadAndPaint();
    };
    qs("#vsp_p467c_prev", m).onclick = ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(Math.max(1, cur-1));
      loadAndPaint();
    };
    qs("#vsp_p467c_next", m).onclick = ()=>{
      const cur = parseInt(lsGet(LS.page,"1"),10)||1;
      setPage(cur+1);
      loadAndPaint();
    };

    qsa("#vsp_p467c_q,#vsp_p467c_overall,#vsp_p467c_degraded,#vsp_p467c_from,#vsp_p467c_to,#vsp_p467c_ps", m).forEach(el=>{
      el.onchange = ()=>{ setPage(1); loadAndPaint(); };
      if(el.id==="vsp_p467c_q") el.oninput = ()=>{ setPage(1); loadAndPaint(); };
    });

    loadAndPaint();
    console.log("[P467c] Runs Pro mounted inside /c/runs card, legacy hidden cleanly");
  }

  function boot(){
    try{ renderIntoCard(); }catch(e){}
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
  setTimeout(boot, 900);
})();
 /* --- /VSP_P467C_FIX_MOUNT_HIDE_LEGACY_V1 --- */
"""
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P467c addon into vsp_c_runs_v1.js")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P467c done. Hard refresh /c/runs (Ctrl+Shift+R). Expect: no old list overlap, menu back to normal layout." | tee -a "$OUT/log.txt"
