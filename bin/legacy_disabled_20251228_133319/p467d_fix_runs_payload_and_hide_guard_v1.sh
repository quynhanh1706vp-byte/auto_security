#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need tee
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

F="static/js/vsp_c_runs_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

start = r";/\* ===================== VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== \*/"
end   = r";/\* ===================== /VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== \*/"

m1 = re.search(start, s)
m2 = re.search(end, s)
if not (m1 and m2 and m2.end() > m1.start()):
    raise SystemExit("[ERR] cannot find P467C block markers to replace")

new_block = r""";/* ===================== VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== */
(function(){
  try{
    // V2 replacement (same marker) – fixes: payload + safe hide + anti-blank
    if(window.__VSP_P467C_RUNS_PRO_CLEAN_V2) return;
    window.__VSP_P467C_RUNS_PRO_CLEAN_V2 = true;

    const log=(...a)=>{ try{ console.log("[P467C2]", ...a); }catch(e){} };

    function esc(x){
      return String(x==null?"":x)
        .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
        .replace(/"/g,"&quot;").replace(/'/g,"&#39;");
    }

    function injectStyles(){
      if(document.getElementById("vsp_p467c2_styles")) return;
      const st=document.createElement("style");
      st.id="vsp_p467c2_styles";
      st.textContent=`
      #vsp_runs_pro_root{max-width:1200px;margin:0 auto 16px auto;padding:10px 12px;}
      .p467c_card{background:rgba(10,14,24,.62);border:1px solid rgba(255,255,255,.08);border-radius:14px;
        box-shadow:0 14px 40px rgba(0,0,0,.35);backdrop-filter: blur(10px);padding:12px 12px;margin:10px 0;}
      .p467c_topbar{position:sticky;top:0;z-index:30;display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between;
        padding:10px 12px;background:rgba(9,12,20,.72);border:1px solid rgba(255,255,255,.08);border-radius:14px;backdrop-filter: blur(10px);}
      .p467c_title{display:flex;gap:10px;align-items:center;min-width:260px}
      .p467c_dot{width:10px;height:10px;border-radius:999px;background:rgba(60,220,120,.9);box-shadow:0 0 18px rgba(60,220,120,.65)}
      .p467c_h1{font-weight:800;letter-spacing:.3px}
      .p467c_sub{font-size:12px;opacity:.75}
      .p467c_row{display:flex;flex-wrap:wrap;gap:10px;align-items:center}
      .p467c_chip{font-size:12px;padding:6px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.10);background:rgba(255,255,255,.04)}
      .p467c_in{height:30px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(0,0,0,.18);color:inherit;padding:0 10px;outline:none}
      .p467c_btn{height:30px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.06);color:inherit;padding:0 10px;cursor:pointer}
      .p467c_btn:hover{background:rgba(255,255,255,.10)}
      .p467c_tbl{width:100%;border-collapse:collapse}
      .p467c_tbl th,.p467c_tbl td{padding:10px 8px;border-bottom:1px solid rgba(255,255,255,.07);font-size:13px}
      .p467c_tbl th{font-size:12px;opacity:.8;text-transform:uppercase;letter-spacing:.4px}
      .p467c_badge{display:inline-block;font-size:12px;padding:4px 8px;border-radius:999px;border:1px solid rgba(255,255,255,.12);background:rgba(255,255,255,.05)}
      .p467c_sel{outline:2px solid rgba(90,140,255,.45);background:rgba(90,140,255,.08)}
      .p467c_actions{display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end}
      .p467c_muted{opacity:.75;font-size:12px}
      `;
      document.head.appendChild(st);
    }

    function mountToBody(){
      // mount to BODY to avoid being hidden by legacy containers
      let root=document.getElementById("vsp_runs_pro_root");
      if(!root){
        root=document.createElement("div");
        root.id="vsp_runs_pro_root";
        document.body.insertBefore(root, document.body.firstChild);
      }else{
        // ensure visible & at top
        if(root.parentElement!==document.body){
          document.body.insertBefore(root, document.body.firstChild);
        }
      }
      root.style.display="";
      root.style.visibility="visible";
      return root;
    }

    function ensureAncestorsVisible(el){
      let cur=el;
      for(let i=0;i<15 && cur && cur!==document.documentElement;i++){
        if(cur.style && cur.style.display==="none"){
          cur.style.display="";
        }
        cur=cur.parentElement;
      }
    }

    function findCardByText(needle){
      needle = String(needle||"").toLowerCase();
      const all = Array.from(document.querySelectorAll("section,div,main,article"));
      let best=null, bestScore=0;
      for(const el of all){
        const t=(el.textContent||"").toLowerCase();
        if(!t.includes(needle)) continue;
        const r=el.getBoundingClientRect();
        const score=(r.width*r.height)+(t.length);
        if(score>bestScore){ best=el; bestScore=score; }
      }
      return best;
    }

    function safeHideLegacy(root){
      // Only hide blocks that look like legacy runs card AND do not contain root.
      const all = Array.from(document.querySelectorAll("section,div,main,article"));
      const cand=[];
      for(const el of all){
        if(!el || el===root) continue;
        if(el.contains(root)) continue;           // critical: never hide ancestor
        if(root.contains(el)) continue;

        const t=(el.textContent||"");
        const hit =
          (t.includes("Pick a RID") && t.includes("Filter by RID")) ||
          (t.includes("Runs loaded:") && t.includes("Download")) ||
          (t.includes("Runs & Reports (real list from /api/vsp/runs)")) ||
          (t.includes("Runs & Reports") && t.includes("Pick a RID"));
        if(hit) cand.append(el);
      }

      // hide only biggest 2-3 blocks (avoid nuking layout)
      cand.sort((a,b)=>{
        const ra=a.getBoundingClientRect(), rb=b.getBoundingClientRect();
        return (rb.width*rb.height)-(ra.width*ra.height);
      });

      const hidden=[];
      for(const el of cand.slice(0,3)){
        let cur=el;
        // bubble up a bit to hide the card container
        for(let i=0;i<4 && cur && cur.parentElement && cur!==document.body;i++){
          const r=cur.getBoundingClientRect();
          if(r.width>700 && r.height>220) break;
          cur=cur.parentElement;
        }
        if(cur && !cur.contains(root) && cur!==root){
          cur.style.display="none";
          hidden.push(cur);
        }
      }
      if(hidden.length) log("legacy blocks hidden:", hidden.length);

      // anti-blank: ensure root ancestors visible
      ensureAncestorsVisible(root);
    }

    function normalizeRunsPayload(j){
      if(!j) return null;
      if(Array.isArray(j)) return j;

      // common shapes
      let arr = null;
      if(Array.isArray(j.items)) arr = j.items;
      else if(Array.isArray(j.runs)) arr = j.runs;
      else if(j.data && Array.isArray(j.data.items)) arr = j.data.items;
      else if(j.result && Array.isArray(j.result.items)) arr = j.result.items;

      return arr;
    }

    async function fetchJson(url){
      const res = await fetch(url, {credentials:"same-origin"});
      const ct = (res.headers.get("content-type")||"").toLowerCase();
      if(!res.ok) throw new Error("http " + res.status + " " + url);
      if(ct.includes("application/json") || ct.includes("text/json") || ct.includes("json")){
        return await res.json();
      }
      // sometimes server returns text but is json
      const txt = await res.text();
      try{ return JSON.parse(txt); }catch(e){ return null; }
    }

    async function fetchRunsAny(limit){
      const L = encodeURIComponent(String(limit||200));
      const urls = [
        `/api/vsp/runs_v3?limit=${L}&include_ci=1`,
        `/api/vsp/runs_v3?limit=${L}`,
        `/api/ui/runs_v3?limit=${L}&include_ci=1`,
        `/api/ui/runs_v3?limit=${L}`,
        `/api/vsp/runs?limit=${L}`,
        `/api/vsp/runs_v2?limit=${L}`,
      ];

      let lastErr=null;
      for(const u of urls){
        try{
          const j = await fetchJson(u);
          const arr = normalizeRunsPayload(j);
          if(arr && Array.isArray(arr)){
            log("runs endpoint ok:", u, "len=", arr.length);
            return arr;
          }
          lastErr = new Error("bad runs payload from " + u);
        }catch(e){
          lastErr = e;
        }
      }
      throw lastErr || new Error("no runs endpoint worked");
    }

    function dedupe(items){
      const m=new Map();
      for(const it of (items||[])){
        const rid = (it && (it.rid||it.RID||it.id)) || "";
        if(!rid) continue;
        const ts = it.ts || it.time || it.date || it.label || "";
        if(!m.has(rid)) m.set(rid, it);
        else{
          const old=m.get(rid);
          const ots = old.ts || old.time || old.date || old.label || "";
          if(String(ts) > String(ots)) m.set(rid, it);
        }
      }
      return Array.from(m.values());
    }
    function fmtDate(it){ return String(it.ts||it.time||it.date||it.label||""); }
    function getOverall(it){ return (it.overall||it.status||it.verdict||it.gate||"UNKNOWN"); }
    function getDegraded(it){
      const v=it.degraded;
      if(v===true) return "DEGRADED";
      if(v===false) return "OK";
      return String(it.degraded_status||"OK");
    }

    function mountUI(){
      injectStyles();
      const root = mountToBody();

      const selRid = new URLSearchParams(location.search||"").get("rid") || "";

      root.innerHTML = `
        <div class="p467c_topbar">
          <div class="p467c_title">
            <span class="p467c_dot"></span>
            <div>
              <div class="p467c_h1">Runs & Reports (commercial)</div>
              <div class="p467c_sub">C/Runs Pro • payload-safe • hide-safe • anti-blank</div>
            </div>
          </div>
          <div class="p467c_row" id="p467c2_stats">
            <span class="p467c_chip">Total <b id="p467c2_total">-</b></span>
            <span class="p467c_chip">Shown <b id="p467c2_shown">-</b></span>
            <span class="p467c_chip">Selected <b id="p467c2_sel">${esc(selRid||"-")}</b></span>
          </div>
        </div>

        <div class="p467c_card">
          <div class="p467c_row" style="justify-content:space-between">
            <div class="p467c_row">
              <input class="p467c_in" id="p467c2_q" placeholder="Search RID..." style="width:220px"/>
              <select class="p467c_in" id="p467c2_ps">
                <option value="20">20/page</option>
                <option value="50">50/page</option>
                <option value="100">100/page</option>
                <option value="200">200/page</option>
              </select>
              <button class="p467c_btn" id="p467c2_refresh">Refresh</button>
            </div>
            <div class="p467c_row">
              <span class="p467c_muted" id="p467c2_msg">Ready.</span>
            </div>
          </div>

          <div style="overflow:auto;margin-top:10px">
            <table class="p467c_tbl">
              <thead>
                <tr>
                  <th style="min-width:260px">RID</th>
                  <th style="min-width:160px">DATE</th>
                  <th style="min-width:110px">OVERALL</th>
                  <th style="min-width:110px">DEGRADED</th>
                  <th style="min-width:360px;text-align:right">ACTIONS</th>
                </tr>
              </thead>
              <tbody id="p467c2_body">
                <tr><td colspan="5" class="p467c_muted">Loading…</td></tr>
              </tbody>
            </table>
          </div>

          <div class="p467c_row" style="justify-content:space-between;margin-top:10px">
            <div class="p467c_row">
              <button class="p467c_btn" id="p467c2_prev">Prev</button>
              <button class="p467c_btn" id="p467c2_next">Next</button>
              <span class="p467c_muted" id="p467c2_page">page -</span>
            </div>
            <div class="p467c_row">
              <button class="p467c_btn" id="p467c2_open_exports">Open Exports</button>
            </div>
          </div>
        </div>

        <div class="p467c_card" id="p467c2_scan_wrap">
          <div class="p467c_h1" style="font-size:14px">Scan / Start Run</div>
          <div class="p467c_muted">Đang lấy panel gốc để giữ nguyên behavior…</div>
        </div>
      `;

      const state={ items:[], page:1, pageSize:20 };
      const $=(id)=>document.getElementById(id);
      const msg=(t)=>{ const el=$("p467c2_msg"); if(el) el.textContent=t; };

      function applyFilter(){
        const q=($("p467c2_q").value||"").trim().toLowerCase();
        let items=state.items.slice();
        if(q) items=items.filter(it=>String(it.rid||it.RID||"").toLowerCase().includes(q));
        return items;
      }

      function render(){
        const body=$("p467c2_body");
        const all=applyFilter();
        $("p467c2_total").textContent=String(state.items.length);
        $("p467c2_shown").textContent=String(all.length);

        const pageCount=Math.max(1, Math.ceil(all.length/state.pageSize));
        state.page=Math.min(Math.max(1,state.page),pageCount);
        $("p467c2_page").textContent=`page ${state.page}/${pageCount}`;

        const start=(state.page-1)*state.pageSize;
        const rows=all.slice(start,start+state.pageSize);

        if(!rows.length){
          body.innerHTML=`<tr><td colspan="5" class="p467c_muted">No runs.</td></tr>`;
          return;
        }

        const sel=new URLSearchParams(location.search||"").get("rid")||"";
        body.innerHTML = rows.map(it=>{
          const rid=it.rid||it.RID||it.id||"";
          const dt=fmtDate(it);
          const overall=getOverall(it);
          const degraded=getDegraded(it);

          const dash=`/c/dashboard?rid=${encodeURIComponent(rid)}`;
          const csv =`/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
          const tgz =`/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}`;

          const trCls=(sel && rid===sel)?"p467c_sel":"";
          return `
            <tr class="${trCls}">
              <td><div style="font-weight:700">${esc(rid)}</div></td>
              <td>${esc(dt)}</td>
              <td><span class="p467c_badge">${esc(overall)}</span></td>
              <td><span class="p467c_badge">${esc(degraded)}</span></td>
              <td style="text-align:right">
                <div class="p467c_actions">
                  <button class="p467c_btn" data-act="copy" data-rid="${esc(rid)}">Copy RID</button>
                  <button class="p467c_btn" data-act="use" data-rid="${esc(rid)}">Use RID</button>
                  <a class="p467c_btn" href="${dash}" target="_blank" rel="noopener" style="text-decoration:none;display:inline-flex;align-items:center">Dashboard</a>
                  <a class="p467c_btn" href="${csv}" target="_blank" rel="noopener" style="text-decoration:none;display:inline-flex;align-items:center">CSV</a>
                  <a class="p467c_btn" href="${tgz}" target="_blank" rel="noopener" style="text-decoration:none;display:inline-flex;align-items:center">Reports.tgz</a>
                </div>
              </td>
            </tr>`;
        }).join("");

        body.querySelectorAll("button[data-act]").forEach(btn=>{
          btn.addEventListener("click", async ()=>{
            const act=btn.getAttribute("data-act");
            const rid=btn.getAttribute("data-rid")||"";
            if(act==="copy"){
              try{ await navigator.clipboard.writeText(rid); msg("Copied: "+rid); }catch(e){ msg("Copy failed."); }
            }else if(act==="use"){
              const u=new URL(location.href);
              u.searchParams.set("rid", rid);
              location.href=u.toString();
            }
          });
        });
      }

      async function load(){
        msg("Loading runs…");
        try{
          const raw = await fetchRunsAny(500);
          const items = dedupe(raw);
          items.sort((a,b)=> String(fmtDate(b)).localeCompare(String(fmtDate(a))));
          state.items = items;
          msg("Loaded.");
          render();
        }catch(e){
          console.error(e);
          msg("Load failed: " + (e && e.message ? e.message : "unknown"));
          $("p467c2_body").innerHTML=`<tr><td colspan="5" class="p467c_muted">Load failed.</td></tr>`;
        }
      }

      $("p467c2_refresh").addEventListener("click", ()=>load());
      $("p467c2_q").addEventListener("input", ()=>{ state.page=1; render(); });
      $("p467c2_ps").addEventListener("change", ()=>{
        state.pageSize=parseInt($("p467c2_ps").value||"20",10)||20;
        state.page=1; render();
      });
      $("p467c2_prev").addEventListener("click", ()=>{ state.page=Math.max(1,state.page-1); render(); });
      $("p467c2_next").addEventListener("click", ()=>{ state.page=state.page+1; render(); });
      $("p467c2_open_exports").addEventListener("click", ()=>{
        try{ window.open("/api/vsp/exports_v1","_blank","noopener"); }catch(e){}
      });

      // Move Scan panel into our card (keep behavior)
      try{
        const scan = findCardByText("Scan / Start Run") || findCardByText("Scan / Start") || null;
        const wrap = document.getElementById("p467c2_scan_wrap");
        if(scan && wrap){
          wrap.innerHTML="";
          wrap.appendChild(scan);
          scan.style.margin="0";
          scan.style.border="0";
          scan.style.background="transparent";
          scan.style.boxShadow="none";
          log("Scan panel moved into Runs Pro");
        }
      }catch(e){}

      // hide legacy safely & anti-blank
      safeHideLegacy(root);

      load();
      log("Runs Pro mounted (C2) for /c/runs");
    }

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", mountUI);
    else mountUI();
  }catch(e){
    try{ console.error("[P467C2] fatal", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== */
"""

# Replace old block with new_block (same markers)
s2 = s[:m1.start()] + new_block + s[m2.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced P467C block with payload-safe + hide-safe V2")
PY

if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P467D done. Hard refresh /c/runs (Ctrl+Shift+R)." | tee -a "$OUT/log.txt"
