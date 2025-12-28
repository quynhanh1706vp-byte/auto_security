#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p468_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_$TS"
echo "[OK] backup => $OUT/$(basename "$F").bak_$TS" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, datetime

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
orig = s

# 1) Remove ALL previous P467* injected blocks to stop double-mount & cand.append crashes
# supports markers like: /* ===================== VSP_P467... */ ... /* ===================== /VSP_P467... */
pat = re.compile(r"""
;?\s*/\*\s*={3,}\s*VSP_P467[^\n]*\s*={0,}\s*\*/   # start marker
.*?
;?\s*/\*\s*={3,}\s*/VSP_P467[^\n]*\s*={0,}\s*\*/ # end marker
""", re.S | re.X)

s2, n = pat.subn("", s)
s = s2

# also neutralize any leftover "P467" guard vars / logs (soft)
s = re.sub(r"__VSP_P467[A-Z0-9_]*", "__VSP_P467_REMOVED", s)

addon = r"""
;/* ===================== VSP_P468_C_RUNS_PRO_ONLY_V1 ===================== */
;(function(){
  try{
    if(window.__VSP_P468_C_RUNS_PRO_ONLY_V1) return;
    window.__VSP_P468_C_RUNS_PRO_ONLY_V1 = true;

    var log = function(){ try{ console.log.apply(console, ["[P468]"].concat([].slice.call(arguments))); }catch(e){} };
    var warn= function(){ try{ console.warn.apply(console, ["[P468]"].concat([].slice.call(arguments))); }catch(e){} };
    var err = function(){ try{ console.error.apply(console, ["[P468]"].concat([].slice.call(arguments))); }catch(e){} };

    function onReady(fn){
      if(document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn, 0);
      document.addEventListener("DOMContentLoaded", fn, {once:true});
    }

    function q(sel, root){ return (root||document).querySelector(sel); }
    function qa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }

    function injectCSS(){
      if(q("#vsp_p468_css")) return;
      var st = document.createElement("style");
      st.id = "vsp_p468_css";
      st.textContent = `
      .vsp-p468-wrap{max-width:1240px;margin:12px auto;padding:0 10px;}
      .vsp-p468-card{background:rgba(9,12,20,.70);border:1px solid rgba(120,140,180,.18);border-radius:14px;
        box-shadow:0 18px 40px rgba(0,0,0,.35);backdrop-filter: blur(10px);padding:12px 12px 10px;margin-bottom:12px;}
      .vsp-p468-h{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;}
      .vsp-p468-h .t{display:flex;align-items:center;gap:10px;font-weight:800;letter-spacing:.2px}
      .vsp-p468-dot{width:10px;height:10px;border-radius:999px;background:rgba(90,220,160,.9);box-shadow:0 0 0 4px rgba(90,220,160,.15);}
      .vsp-p468-sub{opacity:.75;font-size:12px}
      .vsp-p468-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
      .vsp-p468-in{background:rgba(0,0,0,.22);border:1px solid rgba(120,140,180,.18);border-radius:10px;color:inherit;
        padding:7px 10px;font-size:13px;outline:none}
      .vsp-p468-btn{background:rgba(255,255,255,.06);border:1px solid rgba(120,140,180,.18);border-radius:10px;color:inherit;
        padding:7px 10px;font-size:13px;cursor:pointer}
      .vsp-p468-btn:hover{background:rgba(255,255,255,.09)}
      .vsp-p468-pill{display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;
        background:rgba(255,255,255,.06);border:1px solid rgba(120,140,180,.18);font-size:12px;opacity:.9}
      .vsp-p468-grid{width:100%;overflow:auto;border-radius:12px;border:1px solid rgba(120,140,180,.12)}
      .vsp-p468-table{width:100%;border-collapse:separate;border-spacing:0;min-width:860px}
      .vsp-p468-table th,.vsp-p468-table td{padding:10px 10px;border-bottom:1px solid rgba(120,140,180,.10);font-size:13px}
      .vsp-p468-table th{opacity:.75;font-weight:700;text-align:left;background:rgba(255,255,255,.02)}
      .vsp-p468-actions{display:flex;gap:6px;flex-wrap:wrap}
      .vsp-p468-mini{padding:5px 8px;border-radius:999px}
      .vsp-p468-kv{display:flex;gap:10px;flex-wrap:wrap}
      .vsp-p468-kv .k{opacity:.7;font-size:12px}
      .vsp-p468-kv .v{font-weight:700;font-size:12px}
      .vsp-p468-status{margin-top:8px;font-size:12px;opacity:.8}
      `;
      document.head.appendChild(st);
    }

    function closestCard(el){
      if(!el) return null;
      var cur = el;
      for(var i=0;i<10 && cur; i++){
        if(cur.classList && (cur.classList.contains("card") || cur.classList.contains("vsp-card"))) return cur;
        if(cur.tagName && /SECTION|ARTICLE/.test(cur.tagName)) return cur;
        cur = cur.parentElement;
      }
      return el;
    }

    function hideByTextSignature(){
      // hide legacy blocks by their visible text signatures
      var sigs = [
        "Filter by RID",
        "Pick a RID",
        "Runs & Reports",
        "Runs loaded:",
        "real list from /api/vsp/runs"
      ];
      var hidden = 0;

      qa("div,section,article").forEach(function(n){
        try{
          var t = (n.innerText||"").trim();
          if(!t) return;
          var hit = 0;
          for(var i=0;i<sigs.length;i++){
            if(t.includes(sigs[i])) hit++;
          }
          // stronger condition to avoid nuking whole page
          if(hit >= 2){
            var c = closestCard(n);
            if(c && !c.hasAttribute("data-vsp-p468-hidden")){
              c.setAttribute("data-vsp-p468-hidden","1");
              c.style.display = "none";
              hidden++;
            }
          }
        }catch(e){}
      });

      // also hide older mounts if exist
      ["#vsp_p464c_exports_mount","#vsp_runs_legacy","#vsp_runs_old","#vsp_runs_reports_legacy"].forEach(function(sel){
        var x = q(sel);
        if(x && !x.hasAttribute("data-vsp-p468-hidden")){
          x.setAttribute("data-vsp-p468-hidden","1");
          x.style.display="none";
          hidden++;
        }
      });

      log("legacy blocks hidden:", hidden);
    }

    function fmtTS(mtime){
      try{
        if(!mtime) return "";
        var ms = mtime > 2e12 ? mtime : mtime*1000;
        var d = new Date(ms);
        var pad = function(n){ return (n<10?"0":"")+n; };
        return d.getFullYear()+"-"+pad(d.getMonth()+1)+"-"+pad(d.getDate())+" "+pad(d.getHours())+":"+pad(d.getMinutes());
      }catch(e){ return ""; }
    }

    async function fetchJSON(url){
      var res = await fetch(url, {headers: {"Accept":"application/json"}});
      var txt = await res.text();
      try{ return JSON.parse(txt); }catch(e){ return {ok:false, _raw:txt, _status:res.status}; }
    }

    function normalizeRunsPayload(j){
      // Accept multiple shapes:
      // A) {ok:true, runs:[{rid,mtime,...}], total:n}
      // B) {ok:true, runs:[{rid,ts,label,...}], total:n}
      // C) {ok:true, items:[...], total:n}
      if(!j || j.ok !== true) return {ok:false, runs:[], total:0, raw:j};
      var runs = [];
      if(Array.isArray(j.runs)) runs = j.runs;
      else if(Array.isArray(j.items)) runs = j.items;
      else return {ok:false, runs:[], total:0, raw:j};
      var total = (typeof j.total === "number") ? j.total : runs.length;
      return {ok:true, runs:runs, total:total};
    }

    function buildUI(root){
      injectCSS();

      var wrap = document.createElement("div");
      wrap.className = "vsp-p468-wrap";
      wrap.id = "vsp_p468_runs_pro_root";

      // ----- Runs Pro Card -----
      var card = document.createElement("div");
      card.className = "vsp-p468-card";

      var header = document.createElement("div");
      header.className = "vsp-p468-h";
      header.innerHTML = `
        <div class="t"><span class="vsp-p468-dot"></span><div>
          <div>Runs & Reports (commercial)</div>
          <div class="vsp-p468-sub">/c/runs Pro • payload-safe • hide-legacy • anti-blank</div>
        </div></div>
        <div class="vsp-p468-row">
          <span class="vsp-p468-pill" id="p468_total">Total: -</span>
          <span class="vsp-p468-pill" id="p468_shown">Shown: -</span>
          <span class="vsp-p468-pill" id="p468_sel">Selected: -</span>
        </div>
      `;
      card.appendChild(header);

      var controls = document.createElement("div");
      controls.className = "vsp-p468-row";
      controls.style.marginBottom="10px";
      controls.innerHTML = `
        <input class="vsp-p468-in" style="min-width:220px" id="p468_q" placeholder="Search RID..." />
        <select class="vsp-p468-in" id="p468_ps">
          <option value="10">10/page</option>
          <option value="20" selected>20/page</option>
          <option value="50">50/page</option>
          <option value="100">100/page</option>
        </select>
        <button class="vsp-p468-btn" id="p468_refresh">Refresh</button>
        <span class="vsp-p468-status" id="p468_status">Ready.</span>
      `;
      card.appendChild(controls);

      var grid = document.createElement("div");
      grid.className = "vsp-p468-grid";
      grid.innerHTML = `
        <table class="vsp-p468-table">
          <thead><tr>
            <th style="width:340px">RID</th>
            <th style="width:140px">DATE</th>
            <th style="width:140px">OVERALL</th>
            <th style="width:120px">DEGRADED</th>
            <th style="width:320px">ACTIONS</th>
          </tr></thead>
          <tbody id="p468_tb"></tbody>
        </table>
      `;
      card.appendChild(grid);

      var pager = document.createElement("div");
      pager.className="vsp-p468-row";
      pager.style.marginTop="10px";
      pager.innerHTML = `
        <button class="vsp-p468-btn" id="p468_prev">Prev</button>
        <button class="vsp-p468-btn" id="p468_next">Next</button>
        <span class="vsp-p468-sub" id="p468_page">page -</span>
        <div style="flex:1"></div>
        <button class="vsp-p468-btn" id="p468_open_exports">Open Exports</button>
      `;
      card.appendChild(pager);

      wrap.appendChild(card);

      // ----- Scan/Start Run Card -----
      var scan = document.createElement("div");
      scan.className = "vsp-p468-card";
      scan.innerHTML = `
        <div class="vsp-p468-h">
          <div class="t"><span class="vsp-p468-dot"></span><div>
            <div>Scan / Start Run</div>
            <div class="vsp-p468-sub">Kick off via /api/vsp/run_v1 • poll via /api/vsp/run_status_v1</div>
          </div></div>
          <div class="vsp-p468-row">
            <span class="vsp-p468-pill" id="p468_scan_rid">RID: (none)</span>
          </div>
        </div>

        <div class="vsp-p468-row">
          <input class="vsp-p468-in" style="flex:1;min-width:320px" id="p468_target" placeholder="Target path" />
          <select class="vsp-p468-in" style="min-width:220px" id="p468_mode">
            <option value="FULL">FULL (8 tools)</option>
            <option value="FAST">FAST</option>
            <option value="SAFE">SAFE</option>
          </select>
        </div>

        <div class="vsp-p468-row" style="margin-top:8px">
          <input class="vsp-p468-in" style="flex:1;min-width:320px" id="p468_note" placeholder="optional note for audit trail" />
          <button class="vsp-p468-btn" style="min-width:140px" id="p468_start">Start scan</button>
          <button class="vsp-p468-btn" style="min-width:140px" id="p468_poll">Refresh status</button>
        </div>

        <div class="vsp-p468-card" style="margin:10px 0 0 0;padding:10px;background:rgba(0,0,0,.18)">
          <div class="vsp-p468-kv">
            <div><div class="k">state</div><div class="v" id="p468_st_state">-</div></div>
            <div><div class="k">progress</div><div class="v" id="p468_st_prog">-</div></div>
            <div><div class="k">updated</div><div class="v" id="p468_st_upd">-</div></div>
          </div>
          <div class="vsp-p468-status" id="p468_st_msg">Ready.</div>
        </div>
      `;
      wrap.appendChild(scan);

      // mount
      root.insertBefore(wrap, root.firstChild);
      return wrap;
    }

    function getRIDFromURL(){
      try{
        var u = new URL(location.href);
        return u.searchParams.get("rid") || "";
      }catch(e){ return ""; }
    }

    function setRIDInURL(rid){
      try{
        var u = new URL(location.href);
        if(rid) u.searchParams.set("rid", rid);
        else u.searchParams.delete("rid");
        history.replaceState({}, "", u.toString());
      }catch(e){}
    }

    function openExports(){
      // prefer existing exports panel/buttons if present
      var btn = qa("button,a").find(function(x){
        var t=(x.innerText||"").trim().toLowerCase();
        return t==="open exports" || t==="exports" || t==="open";
      });
      if(btn && btn.click) { btn.click(); return; }
      // fallback: scroll to top (exports panel often near top)
      window.scrollTo({top:0, behavior:"smooth"});
    }

    onReady(async function(){
      try{
        // hide legacy FIRST (so even if other scripts render, we suppress them)
        hideByTextSignature();

        // choose a stable root
        var root = window.__VSP_DASH_ROOT ? window.__VSP_DASH_ROOT()
          : (q("#vsp-dashboard-main") || q("#vsp_dashboard_main") || q("#vsp-dashboard") || q("main") || document.body);

        // build UI
        var wrap = buildUI(root);

        // wire up state
        var state = {
          all: [],
          filtered: [],
          page: 1,
          pageSize: 20,
          selected: getRIDFromURL() || (localStorage.getItem("vsp_p468_last_rid")||"")
        };
        if(state.selected) localStorage.setItem("vsp_p468_last_rid", state.selected);

        var elTotal = q("#p468_total");
        var elShown = q("#p468_shown");
        var elSel   = q("#p468_sel");
        var elQ     = q("#p468_q");
        var elPS    = q("#p468_ps");
        var elTB    = q("#p468_tb");
        var elPage  = q("#p468_page");
        var elStatus= q("#p468_status");

        function setStatus(t){ if(elStatus) elStatus.textContent = t; }

        function applyFilter(){
          var qq = (elQ && elQ.value || "").trim().toLowerCase();
          state.filtered = state.all.filter(function(r){
            var rid = String(r.rid || r.run_id || r.name || "");
            if(!rid) return false;
            if(qq && !rid.toLowerCase().includes(qq)) return false;
            return true;
          });
          state.page = 1;
          render();
        }

        function actionButtons(rid){
          var enc = encodeURIComponent(rid);
          // best-effort: keep to endpoints that typically exist in your stack
          var jsonUrl = "/api/vsp/run_file_allow?rid="+enc+"&path=findings_unified.json";
          var csvUrl  = "/api/vsp/exports_v1?rid="+enc+"&what=csv&download=1";
          var tgzUrl  = "/api/vsp/exports_v1?rid="+enc+"&what=tgz&download=1";

          return `
            <div class="vsp-p468-actions">
              <a class="vsp-p468-btn vsp-p468-mini" href="/c/dashboard?rid=${enc}">Dashboard</a>
              <a class="vsp-p468-btn vsp-p468-mini" href="${csvUrl}">CSV</a>
              <a class="vsp-p468-btn vsp-p468-mini" href="${tgzUrl}">TGZ</a>
              <a class="vsp-p468-btn vsp-p468-mini" target="_blank" href="${jsonUrl}">Open JSON</a>
              <button class="vsp-p468-btn vsp-p468-mini" data-act="use" data-rid="${enc}">Use RID</button>
            </div>
          `;
        }

        function render(){
          var total = state.all.length;
          var shown = state.filtered.length;
          if(elTotal) elTotal.textContent = "Total: " + total;
          if(elShown) elShown.textContent = "Shown: " + shown;
          if(elSel) elSel.textContent = "Selected: " + (state.selected || "-");

          var ps = state.pageSize;
          var pages = Math.max(1, Math.ceil(shown / ps));
          if(state.page > pages) state.page = pages;

          var start = (state.page-1)*ps;
          var slice = state.filtered.slice(start, start+ps);

          if(elTB){
            elTB.innerHTML = slice.map(function(r){
              var rid = String(r.rid || r.run_id || r.name || "");
              var mtime = r.mtime || r.mtime_s || r.ts || r.time || r.updated || r.updated_at || 0;
              var date = "";
              if(typeof mtime === "string" && mtime.includes("T")) date = mtime.replace("T"," ").slice(0,16);
              else date = fmtTS(mtime);
              var overall = (r.overall || r.verdict || r.status || "UNKNOWN");
              var degraded = (typeof r.degraded !== "undefined") ? (r.degraded ? "YES":"NO") : (r.degraded_state||"OK");
              return `<tr>
                <td>${rid}</td>
                <td>${date}</td>
                <td>${overall}</td>
                <td>${degraded}</td>
                <td>${actionButtons(rid)}</td>
              </tr>`;
            }).join("") || `<tr><td colspan="5" style="opacity:.7">No runs.</td></tr>`;
          }

          if(elPage) elPage.textContent = "page " + state.page + "/" + pages;
        }

        async function loadRuns(){
          setStatus("Loading…");
          var urls = [
            "/api/vsp/runs?limit=500&offset=0",
            "/api/vsp/runs_v3?limit=500&include_ci=1",
            "/api/vsp/runs_v3?limit=500",
          ];
          var last = null
          for(var i=0;i<urls.length;i++){
            try{
              var j = await fetchJSON(urls[i]);
              var norm = normalizeRunsPayload(j);
              if(norm.ok){
                state.all = norm.runs.map(function(x){
                  // normalize rid + mtime if needed
                  var rid = x.rid || x.run_id || x.name || "";
                  var mtime = x.mtime || x.mtime_s || x.ts || x.time || x.updated || x.updated_at || 0;
                  return Object.assign({}, x, {rid: rid, mtime: mtime});
                });
                // sort newest first when we have mtime
                state.all.sort(function(a,b){
                  var aa = a.mtime || 0, bb = b.mtime || 0;
                  if(typeof aa === "string") aa = Date.parse(aa) || 0;
                  if(typeof bb === "string") bb = Date.parse(bb) || 0;
                  return bb - aa;
                });
                applyFilter();
                setStatus("Ready.");
                return;
              }
              last = j;
            }catch(e){
              last = {ok:false, err:String(e)};
            }
          }
          err("bad runs payload", last);
          setStatus("Error: bad runs payload (check console).");
        }

        // wire controls
        if(elPS){
          elPS.addEventListener("change", function(){
            var v = parseInt(elPS.value, 10);
            state.pageSize = isFinite(v) ? v : 20;
            render();
          });
        }
        if(elQ){
          elQ.addEventListener("input", function(){ applyFilter(); });
        }
        q("#p468_refresh").addEventListener("click", function(){ loadRuns(); });
        q("#p468_prev").addEventListener("click", function(){ state.page = Math.max(1, state.page-1); render(); });
        q("#p468_next").addEventListener("click", function(){
          var pages = Math.max(1, Math.ceil(state.filtered.length / state.pageSize));
          state.page = Math.min(pages, state.page+1); render();
        });
        q("#p468_open_exports").addEventListener("click", function(){ openExports(); });

        // action delegation
        wrap.addEventListener("click", function(ev){
          var t = ev.target;
          if(!t) return;
          var act = t.getAttribute("data-act");
          if(act === "use"){
            var rid = decodeURIComponent(t.getAttribute("data-rid")||"");
            state.selected = rid;
            localStorage.setItem("vsp_p468_last_rid", rid);
            setRIDInURL(rid);
            render();
          }
        });

        // ----- Scan UI wiring -----
        var elTarget = q("#p468_target");
        var elMode   = q("#p468_mode");
        var elNote   = q("#p468_note");
        var elScanRID= q("#p468_scan_rid");
        var stState  = q("#p468_st_state");
        var stProg   = q("#p468_st_prog");
        var stUpd    = q("#p468_st_upd");
        var stMsg    = q("#p468_st_msg");

        // defaults
        if(elTarget && !elTarget.value) elTarget.value = "/home/test/Data/SECURITY_BUNDLE";

        function setScanRID(rid){
          if(!rid) rid = "(none)";
          if(elScanRID) elScanRID.textContent = "RID: " + rid;
        }
        function setScanStatus(j){
          try{
            stState.textContent = (j && (j.state||j.status||j.phase)) ? (j.state||j.status||j.phase) : "-";
            stProg.textContent  = (j && (j.progress||j.pct||j.percent)) ? (j.progress||j.pct||j.percent) : "-";
            stUpd.textContent   = (j && (j.updated||j.ts||j.time)) ? String(j.updated||j.ts||j.time).slice(0,19) : "-";
            stMsg.textContent   = (j && (j.msg||j.message)) ? (j.msg||j.message) : "Ready.";
          }catch(e){}
        }

        var scanRID = localStorage.getItem("vsp_p468_scan_rid") || "";
        if(scanRID) setScanRID(scanRID);

        async function pollStatus(){
          try{
            if(!scanRID) { setScanStatus({message:"No RID yet. Click Start scan first."}); return; }
            var u = "/api/vsp/run_status_v1?rid=" + encodeURIComponent(scanRID);
            var j = await fetchJSON(u);
            setScanStatus(j);
          }catch(e){
            setScanStatus({message:"poll failed: "+String(e)});
          }
        }

        async function startScan(){
          try{
            var body = {
              target_path: (elTarget && elTarget.value || "").trim(),
              mode: (elMode && elMode.value || "FULL"),
              note: (elNote && elNote.value || "").trim()
            };
            stMsg.textContent = "Starting…";
            var res = await fetch("/api/vsp/run_v1", {
              method: "POST",
              headers: {"Content-Type":"application/json"},
              body: JSON.stringify(body)
            });
            var txt = await res.text();
            var j = None
            try{ j = JSON.parse(txt); }catch(e){ j = {ok:false, _raw:txt}; }

            var rid = (j && (j.rid || j.run_id)) ? (j.rid || j.run_id) : "";
            if(rid){
              scanRID = rid;
              localStorage.setItem("vsp_p468_scan_rid", rid);
              setScanRID(rid);
              setScanStatus({message:"Started. Click Refresh status.", status:"STARTED"});
            }else{
              setScanStatus({message:"Start response without rid. Check API contract.", raw:j});
            }
          }catch(e){
            setScanStatus({message:"start failed: "+String(e)});
          }
        }

        q("#p468_poll").addEventListener("click", function(){ pollStatus(); });
        q("#p468_start").addEventListener("click", function(){ startScan(); });

        // finally load runs
        await loadRuns();

      }catch(e){
        err("fatal", e);
      }
    });

  }catch(e){
    try{ console.error("[P468] init error", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P468_C_RUNS_PRO_ONLY_V1 ===================== */
"""

if "VSP_P468_C_RUNS_PRO_ONLY_V1" not in s:
  s = s.rstrip() + "\n\n" + addon + "\n"

p.write_text(s, encoding="utf-8")
print(f"[OK] removed_P467_blocks={n}, appended_P468={( 'VSP_P468_C_RUNS_PRO_ONLY_V1' in s)}")
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"
else
  echo "[WARN] no systemctl in this env; restart manually" | tee -a "$OUT/log.txt"
fi

echo "[OK] Marker check:" | tee -a "$OUT/log.txt"
grep -n "VSP_P468_C_RUNS_PRO_ONLY_V1" -n "$F" | head -n 5 | tee -a "$OUT/log.txt"

echo "[OK] DONE. Now hard refresh /c/runs (Ctrl+Shift+R). If still weird: close tab and reopen /c/runs." | tee -a "$OUT/log.txt"
echo "[OK] Log: $OUT/log.txt"
