#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p470_${TS}"
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
import re

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# strip older injected blocks (P467/P468/P469/P470 old)
def strip_any(tag: str, txt: str) -> str:
    pat = re.compile(
        r";?\s*/\*\s*={3,}\s*"+re.escape(tag)+r"[^\n]*\*/.*?;?\s*/\*\s*={3,}\s*/"+re.escape(tag)+r"[^\n]*\*/",
        re.S
    )
    return pat.sub("", txt)

for tag in [
    "VSP_P467", "VSP_P468", "VSP_P469", "VSP_P470"
]:
    # remove all blocks starting with that prefix if present
    # (works because our tags always start like VSP_P469_...)
    s = re.sub(r";?\s*/\*\s*={3,}\s*"+re.escape(tag)+r".*?={0,}\s*\*/.*?;?\s*/\*\s*={3,}\s*/"+re.escape(tag)+r".*?={0,}\s*\*/",
               "", s, flags=re.S)

addon = r"""
;/* ===================== VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1 ===================== */
;(function(){
  try{
    if(window.__VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1) return;
    window.__VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1 = true;

    var log=function(){ try{ console.log.apply(console, ["[P470]"].concat([].slice.call(arguments))); }catch(e){} };
    var warn=function(){ try{ console.warn.apply(console, ["[P470]"].concat([].slice.call(arguments))); }catch(e){} };

    function q(sel, root){ return (root||document).querySelector(sel); }
    function qa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }
    function onReady(fn){
      if(document.readyState==="complete"||document.readyState==="interactive") return setTimeout(fn,0);
      document.addEventListener("DOMContentLoaded", fn, {once:true});
    }
    function txt(n){ return (n && (n.innerText||n.textContent) || "").trim(); }

    function injectCSS(){
      if(q("#vsp_p470_css")) return;
      var st=document.createElement("style");
      st.id="vsp_p470_css";
      st.textContent = `
        .vsp-p470-wrap{max-width:1200px;margin:0 auto;padding:14px 12px 22px;}
        .vsp-p470-card{
          background:rgba(9,12,20,.70);
          border:1px solid rgba(120,140,180,.18);
          border-radius:14px;
          box-shadow:0 18px 40px rgba(0,0,0,.35);
          backdrop-filter: blur(10px);
          padding:12px;
          margin-top:12px;
        }
        .vsp-p470-head{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px}
        .vsp-p470-title{display:flex;align-items:center;gap:10px;font-weight:800;letter-spacing:.2px}
        .vsp-p470-dot{width:10px;height:10px;border-radius:999px;background:rgba(90,220,160,.9);box-shadow:0 0 0 4px rgba(90,220,160,.15);}
        .vsp-p470-sub{opacity:.75;font-size:12px}
        .vsp-p470-toolbar{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
        .vsp-p470-in{
          background:rgba(0,0,0,.22);
          border:1px solid rgba(120,140,180,.18);
          border-radius:10px;color:inherit;
          padding:7px 10px;font-size:13px;outline:none;
        }
        .vsp-p470-btn{
          background:rgba(255,255,255,.06);
          border:1px solid rgba(120,140,180,.18);
          border-radius:10px;color:inherit;
          padding:7px 10px;font-size:13px;
          cursor:pointer;
        }
        .vsp-p470-btn:hover{background:rgba(255,255,255,.09)}
        .vsp-p470-pill{
          display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;
          background:rgba(255,255,255,.06);
          border:1px solid rgba(120,140,180,.18);
          font-size:12px;opacity:.9
        }
        .vsp-p470-table{width:100%;border-collapse:separate;border-spacing:0 8px}
        .vsp-p470-tr{
          background:rgba(0,0,0,.18);
          border:1px solid rgba(120,140,180,.12);
          border-radius:12px;
        }
        .vsp-p470-tr td{padding:10px 10px;font-size:13px;vertical-align:middle}
        .vsp-p470-tr td:first-child{border-top-left-radius:12px;border-bottom-left-radius:12px}
        .vsp-p470-tr td:last-child{border-top-right-radius:12px;border-bottom-right-radius:12px}
        .vsp-p470-muted{opacity:.72}
        .vsp-p470-actions{display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end}
        .vsp-p470-mini{
          padding:6px 9px;border-radius:10px;
          background:rgba(255,255,255,.06);
          border:1px solid rgba(120,140,180,.18);
          font-size:12px;cursor:pointer;color:inherit;text-decoration:none;
        }
        .vsp-p470-mini:hover{background:rgba(255,255,255,.09)}
        .vsp-p470-footer{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-top:10px}
      `;
      document.head.appendChild(st);
    }

    function hideLegacy(){
      // hide the legacy "Runs & Reports" block and any table containing the signature filter line
      var sig = "Filter by RID / label / date";
      var hidden = 0;
      qa("div,section,article").forEach(function(n){
        var t = txt(n);
        if(!t) return;
        if(t.includes(sig) || t.startsWith("Runs & Reports") || t.includes("Pick a RID - open Dashboard")){
          // BUT don't hide our new card
          if(n.classList && (n.classList.contains("vsp-p470-card") || n.classList.contains("vsp-p470-wrap"))) return;
          // also avoid hiding the top nav container if any
          n.style.display="none";
          hidden++;
        }
      });
      if(hidden) log("legacy hidden:", hidden);
      return hidden;
    }

    function scrapeLegacyRows(){
      // Find a table-like region that contains "Reports.tgz" or "Dashboard CSV"
      var rows = [];
      // try to find all anchors with text "Reports.tgz" (or "Reports.tgz ")
      var tgzLinks = qa("a").filter(function(a){
        var t = (a.textContent||"").trim().toLowerCase();
        return t==="reports.tgz" || t.includes("reports.tgz");
      });

      // walk up to row containers
      tgzLinks.forEach(function(a){
        var row = a;
        for(var i=0;i<12 && row; i++){
          if(row.tagName==="TR") break;
          row = row.parentElement;
        }
        if(!row) return;

        // Extract RID: usually first cell text includes rid
        var rid = "";
        var date = "";
        try{
          var cells = qa("td,th,div", row).slice(0,8);
          // find something that looks like rid
          var all = txt(row);
          var m = all.match(/(VSP_[A-Z0-9_]+|p\d+[a-z0-9_]+_\d{8,}|p\d+_\d{8,}|p\d+[a-z0-9_]+)/);
          if(m) rid = m[1];
          // find date like yyyy-mm-dd or dd/mm
          var md = all.match(/(\d{4}-\d{2}-\d{2}[^ ]*)/);
          if(md) date = md[1];
          if(!date){
            var md2 = all.match(/(\d{2}:\d{2}:\d{2}[^ ]*)/);
            if(md2) date = md2[1];
          }
        }catch(e){}

        // Find action URLs within the same row
        var dash = null, csv = null, tgz = null, useBtn = null;
        var links = qa("a", row);
        links.forEach(function(x){
          var tt = (x.textContent||"").trim().toLowerCase();
          if(tt==="dashboard") dash = x.getAttribute("href");
          if(tt==="csv") csv = x.getAttribute("href");
          if(tt.includes("reports.tgz") || tt==="tgz") tgz = x.getAttribute("href");
        });
        var btns = qa("button", row);
        btns.forEach(function(b){
          var tt = (b.textContent||"").trim().toLowerCase();
          if(tt.includes("use rid")) useBtn = b;
        });

        // Deduplicate by rid
        if(rid && !rows.some(function(r){ return r.rid===rid; })){
          rows.push({rid:rid, date:date||"", dash:dash, csv:csv, tgz:tgz});
        }
      });

      // fallback: if no tgz links found, try to find rows by "Dashboard CSV"
      if(rows.length===0){
        qa("tr").forEach(function(tr){
          var t = txt(tr);
          if(t.includes("Dashboard") && t.includes("CSV")){
            var m = t.match(/(VSP_[A-Z0-9_]+|p\d+[a-z0-9_]+_\d{8,}|p\d+_\d{8,}|p\d+[a-z0-9_]+)/);
            if(!m) return;
            var rid = m[1];
            var dash=null,csv=null,tgz=null;
            qa("a", tr).forEach(function(x){
              var tt=(x.textContent||"").trim().toLowerCase();
              if(tt==="dashboard") dash=x.getAttribute("href");
              if(tt==="csv") csv=x.getAttribute("href");
              if(tt.includes("reports.tgz")||tt==="tgz") tgz=x.getAttribute("href");
            });
            if(!rows.some(function(r){ return r.rid===rid; })){
              rows.push({rid:rid, date:"", dash:dash, csv:csv, tgz:tgz});
            }
          }
        });
      }

      // sort newest-ish: rid contains timestamp, just reverse as-is if already in DOM order
      return rows;
    }

    function buildProUI(){
      injectCSS();

      // mount point: place after the top "VSP • Commercial" header if possible; else body
      var anchor = qa("h1,h2,div").find(function(n){
        var t = txt(n);
        return t.includes("VSP") && t.includes("Commercial");
      });
      var parent = (anchor && anchor.closest && anchor.closest("div")) || document.body;

      // avoid double mount
      if(q("#vsp_p470_root")) return true;

      var wrap = document.createElement("div");
      wrap.id = "vsp_p470_root";
      wrap.className = "vsp-p470-wrap";

      // Runs Pro card
      var card = document.createElement("div");
      card.className = "vsp-p470-card";
      card.innerHTML = `
        <div class="vsp-p470-head">
          <div>
            <div class="vsp-p470-title"><span class="vsp-p470-dot"></span><span>Runs & Reports (commercial)</span></div>
            <div class="vsp-p470-sub">Pro-only • legacy hidden • scrape-safe</div>
          </div>
          <div class="vsp-p470-toolbar">
            <span class="vsp-p470-pill" id="p470_stat_total">Total: -</span>
            <span class="vsp-p470-pill" id="p470_stat_shown">Shown: -</span>
            <span class="vsp-p470-pill" id="p470_stat_sel">Selected: -</span>
          </div>
        </div>

        <div class="vsp-p470-toolbar" style="margin-bottom:10px">
          <input id="p470_q" class="vsp-p470-in" placeholder="Search RID..." style="min-width:260px;flex:1"/>
          <select id="p470_pagesz" class="vsp-p470-in" style="min-width:140px">
            <option value="20">20/page</option>
            <option value="50">50/page</option>
            <option value="100">100/page</option>
          </select>
          <button id="p470_refresh" class="vsp-p470-btn">Refresh</button>
          <button id="p470_open_exports" class="vsp-p470-btn">Open Exports</button>
        </div>

        <table class="vsp-p470-table" id="p470_tbl">
          <thead>
            <tr class="vsp-p470-muted">
              <td style="width:40%">RID</td>
              <td style="width:20%">DATE</td>
              <td style="width:40%;text-align:right">ACTIONS</td>
            </tr>
          </thead>
          <tbody id="p470_tbody"></tbody>
        </table>

        <div class="vsp-p470-footer">
          <div class="vsp-p470-muted" id="p470_hint">Tip: Use RID to pin then open Dashboard.</div>
          <div class="vsp-p470-toolbar">
            <button class="vsp-p470-btn" id="p470_prev">Prev</button>
            <span class="vsp-p470-pill" id="p470_page">page 1</span>
            <button class="vsp-p470-btn" id="p470_next">Next</button>
          </div>
        </div>
      `;

      // Scan card (we will move legacy scan block content into here)
      var scan = document.createElement("div");
      scan.className = "vsp-p470-card";
      scan.innerHTML = `
        <div class="vsp-p470-head">
          <div>
            <div class="vsp-p470-title"><span class="vsp-p470-dot"></span><span>Scan / Start Run</span></div>
            <div class="vsp-p470-sub">Kick off + poll status • commercial layout</div>
          </div>
          <div class="vsp-p470-toolbar">
            <span class="vsp-p470-pill" id="p470_scan_rid">RID: (none)</span>
          </div>
        </div>
        <div id="p470_scan_mount" class="vsp-p470-toolbar" style="flex-direction:column;align-items:stretch;gap:10px"></div>
      `;

      wrap.appendChild(card);
      wrap.appendChild(scan);

      // insert wrap near top of content (after nav-ish)
      if(parent.firstChild) parent.insertBefore(wrap, parent.firstChild.nextSibling || parent.firstChild);
      else parent.appendChild(wrap);

      return true;
    }

    function moveScanIntoPro(){
      var mount = q("#p470_scan_mount");
      if(!mount) return;

      // find legacy scan block by text
      var legacy = qa("div,section,article").find(function(n){
        var t = txt(n);
        return t.includes("Scan / Start Run") && t.includes("Kick off via");
      });
      if(!legacy) return;

      // grab inputs/selects/buttons from legacy
      var inputs = qa("input", legacy);
      var selects = qa("select", legacy);
      var buttons = qa("button", legacy);

      // style them
      inputs.forEach(function(i){ i.classList.add("vsp-p470-in"); i.style.width="100%"; });
      selects.forEach(function(s){ s.classList.add("vsp-p470-in"); s.style.minWidth="240px"; });
      buttons.forEach(function(b){ b.classList.add("vsp-p470-btn"); b.style.minWidth="160px"; });

      // Create rows
      var row1 = document.createElement("div"); row1.className="vsp-p470-toolbar";
      var row2 = document.createElement("div"); row2.className="vsp-p470-toolbar";

      // heuristics: first input=target, second=note
      if(inputs[0]){ inputs[0].placeholder = inputs[0].placeholder || "Target path"; row1.appendChild(inputs[0]); }
      if(selects[0]) row1.appendChild(selects[0]);

      // buttons: Start scan + Refresh status
      var startBtn = buttons.find(function(b){ return (b.textContent||"").toLowerCase().includes("start"); }) || buttons[0];
      var refBtn   = buttons.find(function(b){ return (b.textContent||"").toLowerCase().includes("refresh"); }) || buttons[1];

      if(inputs[1]){ inputs[1].placeholder = inputs[1].placeholder || "Optional note for audit trail"; row2.appendChild(inputs[1]); }
      if(startBtn) row2.appendChild(startBtn);
      if(refBtn) row2.appendChild(refBtn);

      // mount
      mount.innerHTML="";
      mount.appendChild(row1);
      mount.appendChild(row2);

      // hide legacy scan block now
      legacy.style.display="none";
      log("scan moved into pro");
    }

    function renderRows(rows, page, pageSize, query){
      var tbody = q("#p470_tbody");
      if(!tbody) return;
      tbody.innerHTML="";

      var filtered = rows;
      if(query){
        var ql = query.toLowerCase();
        filtered = rows.filter(function(r){ return (r.rid||"").toLowerCase().includes(ql); });
      }

      var total = filtered.length;
      var maxPage = Math.max(1, Math.ceil(total / pageSize));
      if(page > maxPage) page = maxPage;
      if(page < 1) page = 1;

      var start = (page-1)*pageSize;
      var slice = filtered.slice(start, start+pageSize);

      slice.forEach(function(r){
        var tr = document.createElement("tr");
        tr.className="vsp-p470-tr";
        var rid = r.rid || "";
        var date = r.date || "";

        var actions = document.createElement("div");
        actions.className="vsp-p470-actions";

        function mkA(label, href){
          if(!href) return null;
          var a = document.createElement("a");
          a.className="vsp-p470-mini";
          a.textContent = label;
          a.href = href;
          a.target = "_blank";
          a.rel = "noopener";
          return a;
        }
        function mkBtn(label, fn){
          var b = document.createElement("button");
          b.className="vsp-p470-mini";
          b.type="button";
          b.textContent = label;
          b.addEventListener("click", fn);
          return b;
        }

        // Dashboard / CSV / TGZ from scraped links
        var aDash = mkA("Dashboard", r.dash);
        var aCSV  = mkA("CSV", r.csv);
        var aTGZ  = mkA("TGZ", r.tgz);

        if(aDash) actions.appendChild(aDash);
        if(aCSV) actions.appendChild(aCSV);
        if(aTGZ) actions.appendChild(aTGZ);

        // Copy RID
        actions.appendChild(mkBtn("Copy RID", function(){
          try{ navigator.clipboard.writeText(rid); }catch(e){}
        }));

        // Use RID: reuse existing global buttons if present
        actions.appendChild(mkBtn("Use RID", function(){
          try{
            // try to click existing "USE RID" top button if exists (common in your UI)
            var topUse = qa("button").find(function(b){ return (b.textContent||"").trim().toLowerCase()==="use rid"; });
            if(topUse){
              // set any visible RID input if exists
              var inp = qa("input").find(function(i){ return (i.placeholder||"").toLowerCase().includes("rid"); });
              if(inp){ inp.value = rid; inp.dispatchEvent(new Event("input",{bubbles:true})); }
              topUse.click();
            }else{
              // fallback: set query param rid and reload
              var u = new URL(window.location.href);
              u.searchParams.set("rid", rid);
              window.location.href = u.toString();
            }
            var sel = q("#p470_stat_sel");
            if(sel) sel.textContent = "Selected: " + rid;
          }catch(e){}
        }));

        tr.innerHTML = `
          <td><div style="font-weight:700">${rid}</div></td>
          <td class="vsp-p470-muted">${date || "-"}</td>
          <td style="text-align:right"></td>
        `;
        tr.children[2].appendChild(actions);
        tbody.appendChild(tr);
      });

      var stTot = q("#p470_stat_total");
      var stSho = q("#p470_stat_shown");
      var pg = q("#p470_page");
      if(stTot) stTot.textContent = "Total: " + rows.length;
      if(stSho) stSho.textContent = "Shown: " + total;
      if(pg) pg.textContent = "page " + page + "/" + Math.max(1, Math.ceil(total/pageSize));

      // store page state
      window.__p470_state = {rows:rows, filteredTotal:total, page:page, pageSize:pageSize, query:query||""};
    }

    function wireEvents(rows){
      var qIn = q("#p470_q");
      var ps = q("#p470_pagesz");
      var rf = q("#p470_refresh");
      var prev = q("#p470_prev");
      var next = q("#p470_next");
      var openExp = q("#p470_open_exports");

      function redraw(resetPage){
        var st = window.__p470_state || {page:1,pageSize:20,query:""};
        var page = resetPage ? 1 : (st.page||1);
        var pageSize = parseInt((ps && ps.value) || (st.pageSize||20), 10) || 20;
        var query = (qIn && qIn.value) || st.query || "";
        renderRows(rows, page, pageSize, query);
      }

      if(qIn){
        qIn.addEventListener("input", function(){ redraw(true); });
      }
      if(ps){
        ps.addEventListener("change", function(){ redraw(true); });
      }
      if(rf){
        rf.addEventListener("click", function(){
          // re-scrape from DOM again
          try{
            var nr = scrapeLegacyRows();
            rows.length = 0;
            nr.forEach(function(x){ rows.push(x); });
            hideLegacy();
            moveScanIntoPro();
            redraw(true);
          }catch(e){ warn("refresh failed", e); }
        });
      }
      if(prev){
        prev.addEventListener("click", function(){
          var st = window.__p470_state || {};
          var page = Math.max(1, (st.page||1) - 1);
          renderRows(rows, page, st.pageSize||20, st.query||"");
        });
      }
      if(next){
        next.addEventListener("click", function(){
          var st = window.__p470_state || {};
          var page = (st.page||1) + 1;
          renderRows(rows, page, st.pageSize||20, st.query||"");
        });
      }
      if(openExp){
        openExp.addEventListener("click", function(){
          // try to click existing "Open Exports" if exists, else scroll bottom
          var btn = qa("button,a").find(function(x){
            var t=(x.textContent||"").toLowerCase();
            return t.includes("open exports");
          });
          if(btn && btn!==openExp){ try{ btn.click(); }catch(e){} }
          else window.scrollTo({top:document.body.scrollHeight, behavior:"smooth"});
        });
      }
    }

    function apply(){
      buildProUI();

      // scrape legacy BEFORE hiding (if possible)
      var rows = scrapeLegacyRows();
      if(!rows || !rows.length){
        log("no legacy rows scraped yet");
      }else{
        log("scraped rows:", rows.length);
      }

      hideLegacy();
      moveScanIntoPro();

      renderRows(rows, 1, 20, "");
      wireEvents(rows);

      // mark selected rid from URL
      try{
        var u = new URL(window.location.href);
        var rid = u.searchParams.get("rid") || "";
        if(rid && q("#p470_stat_sel")) q("#p470_stat_sel").textContent = "Selected: " + rid;
      }catch(e){}
    }

    onReady(function(){
      apply();
      // Observer: if legacy UI renders again, hide it & re-scrape
      var mo = new MutationObserver(function(){
        try{
          hideLegacy();
          moveScanIntoPro();
        }catch(e){}
      });
      mo.observe(document.documentElement, {subtree:true, childList:true});
      log("observer on");
    });

  }catch(e){
    try{ console.error("[P470] init error", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1 ===================== */
"""

if "VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1" not in s:
    s = s.rstrip() + "\n\n" + addon + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] wrote P470 addon")
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"
else
  echo "[WARN] no systemctl; restart manually" | tee -a "$OUT/log.txt"
fi

echo "[OK] Marker check:" | tee -a "$OUT/log.txt"
grep -n "VSP_P470_C_RUNS_PRO_ONLY_AND_SCAN_V1" -n "$F" | head -n 5 | tee -a "$OUT/log.txt"

echo "[OK] DONE. Close tab /c/runs, reopen /c/runs, then Ctrl+Shift+R." | tee -a "$OUT/log.txt"
echo "[OK] Log: $OUT/log.txt"
