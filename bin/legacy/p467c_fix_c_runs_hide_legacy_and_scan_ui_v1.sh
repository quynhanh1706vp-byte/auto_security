#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p467c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need bash; need python3; need date; need ls; need head; need grep; need sed
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

F="static/js/vsp_c_runs_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

echo "[INFO] OUT=$OUT" | tee -a "$OUT/log.txt"

# 1) restore from latest backup that definitely exists (prefer p467b/p467* backups)
bk=""
bk="$(ls -1t out_ci/p467b_*/vsp_c_runs_v1.js.bak_* 2>/dev/null | head -n1 || true)"
if [ -z "${bk}" ]; then
  bk="$(ls -1t out_ci/p467*_*/vsp_c_runs_v1.js.bak_* 2>/dev/null | head -n1 || true)"
fi
if [ -z "${bk}" ]; then
  bk="$(ls -1t out_ci/*/vsp_c_runs_v1.js.bak_* 2>/dev/null | head -n1 || true)"
fi

if [ -z "${bk}" ]; then
  echo "[ERR] cannot find any backup out_ci/*/vsp_c_runs_v1.js.bak_*" | tee -a "$OUT/log.txt"
  echo "[HINT] run: ls -1t out_ci/*/vsp_c_runs_v1.js.bak_* | head" | tee -a "$OUT/log.txt"
  exit 2
fi

cp -f "$F" "$OUT/$(basename "$F").before_${TS}"
cp -f "$bk" "$F"
echo "[OK] restored $F <= $bk" | tee -a "$OUT/log.txt"

# 2) append CLEAN Runs Pro (idempotent)
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_runs_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
mark="VSP_P467C_RUNS_PRO_CLEAN_V1"
if mark in s:
    print("[OK] marker exists; skip append")
    raise SystemExit(0)

addon = r"""
;/* ===================== VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== */
(function(){
  try{
    if(window.__VSP_P467C_RUNS_PRO_CLEAN_V1) return;
    window.__VSP_P467C_RUNS_PRO_CLEAN_V1 = true;

    const log = (...a)=>{ try{ console.log("[P467C]", ...a); }catch(e){} };

    function esc(s){
      return String(s==null?"":s)
        .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
        .replace(/"/g,"&quot;").replace(/'/g,"&#39;");
    }

    function pickMainAnchor(){
      return document.querySelector("#vsp_c_main")
        || document.querySelector("#vsp-dashboard-main")
        || document.querySelector("main")
        || document.body;
    }

    function findCardByText(needle){
      needle = String(needle||"").toLowerCase();
      const all = Array.from(document.querySelectorAll("section,div,main,article"));
      let best=null, bestScore=0;
      for(const el of all){
        const t = (el.textContent||"").toLowerCase();
        if(!t.includes(needle)) continue;
        const r = el.getBoundingClientRect();
        const score = (r.width*r.height) + (t.length);
        if(score > bestScore){
          best=el; bestScore=score;
        }
      }
      return best;
    }

    function hideLegacyRunsSafely(keepEl){
      const candidates = [];
      const all = Array.from(document.querySelectorAll("section,div,main,article"));
      for(const el of all){
        if(!el || el===keepEl || keepEl.contains(el)) continue;
        const t = (el.textContent||"");
        // legacy signatures we saw on old UI
        if(t.includes("Pick a RID") && t.includes("Filter by RID")) candidates.push(el);
        else if(t.includes("Runs loaded:") && t.includes("Download")) candidates.push(el);
        else if(t.includes("Runs & Reports") && t.includes("Pick a RID")) candidates.push(el);
        else if(t.includes("Runs & Reports (real list from /api/vsp/runs)")) candidates.push(el);
      }
      // hide big ones first
      candidates.sort((a,b)=>{
        const ra=a.getBoundingClientRect(), rb=b.getBoundingClientRect();
        return (rb.width*rb.height)-(ra.width*ra.height);
      });

      const hidden = new Set();
      for(const el of candidates.slice(0,10)){
        let cur = el;
        for(let i=0;i<5 && cur && cur!==document.body;i++){
          const r = cur.getBoundingClientRect();
          if(r.width>500 && r.height>180) break;
          cur = cur.parentElement;
        }
        if(cur && !hidden.has(cur) && cur!==keepEl && !keepEl.contains(cur)){
          hidden.add(cur);
          cur.style.display="none";
        }
      }
      if(hidden.size) log("legacy blocks hidden:", hidden.size);
    }

    function injectStyles(){
      if(document.getElementById("vsp_p467c_styles")) return;
      const st=document.createElement("style");
      st.id="vsp_p467c_styles";
      st.textContent = `
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

    async function fetchRuns(limit){
      const url = "/api/vsp/runs?limit=" + encodeURIComponent(String(limit||200));
      const res = await fetch(url, {credentials:"same-origin"});
      const j = await res.json().catch(()=>null);
      if(!j || !j.items) throw new Error("bad runs payload");
      return j.items;
    }

    function dedupe(items){
      const m = new Map();
      for(const it of (items||[])){
        const rid = (it && (it.rid||it.RID||it.id)) || "";
        if(!rid) continue;
        const ts = it.ts || it.time || it.date || it.label || "";
        // keep first seen (usually newest if API already sorted); otherwise compare lexical ts
        if(!m.has(rid)) m.set(rid, it);
        else{
          const old = m.get(rid);
          const ots = old.ts || old.time || old.date || old.label || "";
          if(String(ts) > String(ots)) m.set(rid, it);
        }
      }
      return Array.from(m.values());
    }

    function fmtDate(it){
      const d = it.ts || it.time || it.date || it.label || "";
      return String(d||"");
    }

    function getOverall(it){
      return (it.overall || it.status || it.verdict || it.gate || "UNKNOWN");
    }

    function getDegraded(it){
      const v = it.degraded;
      if(v===true) return "DEGRADED";
      if(v===false) return "OK";
      return (it.degraded_status || "OK");
    }

    function mountUI(){
      injectStyles();
      const anchor = pickMainAnchor();

      // root
      let root = document.getElementById("vsp_runs_pro_root");
      if(!root){
        root = document.createElement("div");
        root.id = "vsp_runs_pro_root";
        if(anchor===document.body) document.body.insertBefore(root, document.body.firstChild);
        else anchor.insertBefore(root, anchor.firstChild);
      }

      const selRid = new URLSearchParams(location.search||"").get("rid") || "";

      root.innerHTML = `
        <div class="p467c_topbar">
          <div class="p467c_title">
            <span class="p467c_dot"></span>
            <div>
              <div class="p467c_h1">Runs & Reports (commercial)</div>
              <div class="p467c_sub">C/Runs Pro • toolbar + dedupe + keep selected</div>
            </div>
          </div>
          <div class="p467c_row" id="p467c_stats">
            <span class="p467c_chip">Total <b id="p467c_total">-</b></span>
            <span class="p467c_chip">Shown <b id="p467c_shown">-</b></span>
            <span class="p467c_chip">Selected <b id="p467c_sel">${esc(selRid||"-")}</b></span>
          </div>
        </div>

        <div class="p467c_card">
          <div class="p467c_row" style="justify-content:space-between">
            <div class="p467c_row">
              <input class="p467c_in" id="p467c_q" placeholder="Search RID..." style="width:220px"/>
              <select class="p467c_in" id="p467c_ps">
                <option value="20">20/page</option>
                <option value="50">50/page</option>
                <option value="100">100/page</option>
                <option value="200">200/page</option>
              </select>
              <button class="p467c_btn" id="p467c_refresh">Refresh</button>
            </div>
            <div class="p467c_row">
              <span class="p467c_muted" id="p467c_msg">Ready.</span>
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
              <tbody id="p467c_body">
                <tr><td colspan="5" class="p467c_muted">Loading…</td></tr>
              </tbody>
            </table>
          </div>

          <div class="p467c_row" style="justify-content:space-between;margin-top:10px">
            <div class="p467c_row">
              <button class="p467c_btn" id="p467c_prev">Prev</button>
              <button class="p467c_btn" id="p467c_next">Next</button>
              <span class="p467c_muted" id="p467c_page">page -</span>
            </div>
            <div class="p467c_row">
              <button class="p467c_btn" id="p467c_open_exports">Open Exports</button>
            </div>
          </div>
        </div>

        <div class="p467c_card" id="p467c_scan_wrap">
          <div class="p467c_h1" style="font-size:14px">Scan / Start Run</div>
          <div class="p467c_muted">Đang lấy panel gốc để giữ nguyên behavior…</div>
        </div>
      `;

      const state = { items: [], page: 1, pageSize: 20 };

      const $ = (id)=>document.getElementById(id);
      const msg = (t)=>{ const el=$("p467c_msg"); if(el) el.textContent = t; };

      function applyFilter(){
        const q = ($("p467c_q").value||"").trim().toLowerCase();
        let items = state.items.slice();
        if(q) items = items.filter(it => String(it.rid||it.RID||"").toLowerCase().includes(q));
        return items;
      }

      function render(){
        const body = $("p467c_body");
        const all = applyFilter();
        $("p467c_total").textContent = String(state.items.length);
        $("p467c_shown").textContent = String(all.length);

        const pageCount = Math.max(1, Math.ceil(all.length / state.pageSize));
        state.page = Math.min(Math.max(1, state.page), pageCount);
        $("p467c_page").textContent = `page ${state.page}/${pageCount}`;

        const start = (state.page-1)*state.pageSize;
        const rows = all.slice(start, start+state.pageSize);

        if(!rows.length){
          body.innerHTML = `<tr><td colspan="5" class="p467c_muted">No runs.</td></tr>`;
          return;
        }

        const sel = new URLSearchParams(location.search||"").get("rid") || "";
        body.innerHTML = rows.map(it=>{
          const rid = it.rid || it.RID || "";
          const dt = fmtDate(it);
          const overall = getOverall(it);
          const degraded = getDegraded(it);

          const dash = `/c/dashboard?rid=${encodeURIComponent(rid)}`;
          const csv  = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
          const tgz  = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}`;

          const trCls = (sel && rid===sel) ? "p467c_sel" : "";
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

        // actions
        body.querySelectorAll("button[data-act]").forEach(btn=>{
          btn.addEventListener("click", async ()=>{
            const act = btn.getAttribute("data-act");
            const rid = btn.getAttribute("data-rid") || "";
            if(act==="copy"){
              try{ await navigator.clipboard.writeText(rid); msg("Copied: " + rid); }
              catch(e){ msg("Copy failed."); }
            }else if(act==="use"){
              const u = new URL(location.href);
              u.searchParams.set("rid", rid);
              location.href = u.toString();
            }
          });
        });
      }

      async function load(){
        msg("Loading runs…");
        try{
          const raw = await fetchRuns(500);
          const items = dedupe(raw);
          // sort newest first (best-effort)
          items.sort((a,b)=> String(fmtDate(b)).localeCompare(String(fmtDate(a))));
          state.items = items;
          msg("Loaded.");
          render();
        }catch(e){
          console.error(e);
          msg("Load failed. Check console.");
          $("p467c_body").innerHTML = `<tr><td colspan="5" class="p467c_muted">Load failed.</td></tr>`;
        }
      }

      $("p467c_refresh").addEventListener("click", ()=>load());
      $("p467c_q").addEventListener("input", ()=>{ state.page=1; render(); });
      $("p467c_ps").addEventListener("change", ()=>{
        state.pageSize = parseInt($("p467c_ps").value||"20",10) || 20;
        state.page=1; render();
      });
      $("p467c_prev").addEventListener("click", ()=>{ state.page=Math.max(1, state.page-1); render(); });
      $("p467c_next").addEventListener("click", ()=>{ state.page=state.page+1; render(); });
      $("p467c_open_exports").addEventListener("click", ()=>{
        try{ window.open("/api/vsp/exports_v1","_blank","noopener"); }catch(e){}
      });

      // 3) Move Scan/Start Run panel into our pro card (keep behavior)
      try{
        const scan = findCardByText("Scan / Start Run") || findCardByText("Scan / Start") || null;
        const wrap = document.getElementById("p467c_scan_wrap");
        if(scan && wrap){
          // move the whole container to keep event handlers
          wrap.innerHTML = "";
          wrap.appendChild(scan);
          // make it look like our card
          scan.style.margin = "0";
          scan.style.border = "0";
          scan.style.background = "transparent";
          scan.style.boxShadow = "none";
          log("Scan panel moved into Runs Pro");
        }else{
          log("Scan panel not found; keep placeholder");
        }
      }catch(e){}

      // finally: hide legacy blocks (but keep our root)
      hideLegacyRunsSafely(root);

      load();
      log("Runs Pro mounted for /c/runs");
    }

    if(document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", mountUI);
    }else{
      mountUI();
    }
  }catch(e){
    try{ console.error("[P467C] fatal", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P467C_RUNS_PRO_CLEAN_V1 ===================== */
"""
p.write_text(s + ("\n" if not s.endswith("\n") else "") + addon, encoding="utf-8")
print("[OK] appended P467C addon")
PY

echo "[OK] py_compile not applicable for JS; done append" | tee -a "$OUT/log.txt"

if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P467C done. Hard refresh /c/runs (Ctrl+Shift+R)." | tee -a "$OUT/log.txt"
echo "[HINT] If you still see old UI, close tab and reopen /c/runs." | tee -a "$OUT/log.txt"
