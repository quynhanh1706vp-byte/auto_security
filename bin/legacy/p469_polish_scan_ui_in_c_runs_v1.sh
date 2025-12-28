#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p469_${TS}"
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

def strip_block(tag_prefix: str, s: str):
    # remove blocks like: /* === TAG === */ ... /* === /TAG === */
    pat = re.compile(
        r";?\s*/\*\s*={3,}\s*"+re.escape(tag_prefix)+r"[^\n]*\s*={0,}\s*\*/.*?;?\s*/\*\s*={3,}\s*/"+re.escape(tag_prefix)+r"[^\n]*\s*={0,}\s*\*/",
        re.S
    )
    return pat.sub("", s)

# remove prior injected blocks that might fight each other
for tag in ["VSP_P467", "VSP_P468"]:
    s = strip_block(tag, s)

addon = r"""
;/* ===================== VSP_P469_SCAN_POLISH_C_RUNS_V1 ===================== */
;(function(){
  try{
    if(window.__VSP_P469_SCAN_POLISH_C_RUNS_V1) return;
    window.__VSP_P469_SCAN_POLISH_C_RUNS_V1 = true;

    var log = function(){ try{ console.log.apply(console, ["[P469]"].concat([].slice.call(arguments))); }catch(e){} };
    var warn= function(){ try{ console.warn.apply(console, ["[P469]"].concat([].slice.call(arguments))); }catch(e){} };

    function q(sel, root){ return (root||document).querySelector(sel); }
    function qa(sel, root){ return Array.prototype.slice.call((root||document).querySelectorAll(sel)); }

    function onReady(fn){
      if(document.readyState === "complete" || document.readyState === "interactive") return setTimeout(fn,0);
      document.addEventListener("DOMContentLoaded", fn, {once:true});
    }

    function injectCSS(){
      if(q("#vsp_p469_css")) return;
      var st = document.createElement("style");
      st.id = "vsp_p469_css";
      st.textContent = `
        .vsp-p469-scan-card{
          background:rgba(9,12,20,.70);
          border:1px solid rgba(120,140,180,.18);
          border-radius:14px;
          box-shadow:0 18px 40px rgba(0,0,0,.35);
          backdrop-filter: blur(10px);
          padding:12px 12px 10px;
          margin-top:10px;
        }
        .vsp-p469-scan-head{
          display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;
        }
        .vsp-p469-scan-title{display:flex;align-items:center;gap:10px;font-weight:800;letter-spacing:.2px}
        .vsp-p469-dot{width:10px;height:10px;border-radius:999px;background:rgba(90,220,160,.9);box-shadow:0 0 0 4px rgba(90,220,160,.15);}
        .vsp-p469-sub{opacity:.75;font-size:12px}
        .vsp-p469-row{display:flex;flex-wrap:wrap;gap:8px;align-items:center}
        .vsp-p469-in{
          background:rgba(0,0,0,.22);
          border:1px solid rgba(120,140,180,.18);
          border-radius:10px;
          color:inherit;
          padding:7px 10px;
          font-size:13px;
          outline:none;
        }
        .vsp-p469-btn{
          background:rgba(255,255,255,.06);
          border:1px solid rgba(120,140,180,.18);
          border-radius:10px;
          color:inherit;
          padding:7px 10px;
          font-size:13px;
          cursor:pointer;
          min-width:140px;
        }
        .vsp-p469-btn:hover{background:rgba(255,255,255,.09)}
        .vsp-p469-pill{
          display:inline-flex;align-items:center;gap:6px;padding:6px 10px;border-radius:999px;
          background:rgba(255,255,255,.06);
          border:1px solid rgba(120,140,180,.18);
          font-size:12px;opacity:.9
        }
        .vsp-p469-statusbox{
          margin-top:10px;
          padding:10px;
          border-radius:12px;
          border:1px solid rgba(120,140,180,.12);
          background:rgba(0,0,0,.18);
          font-size:12px;
          opacity:.9
        }
        .vsp-p469-kv{display:flex;gap:14px;flex-wrap:wrap}
        .vsp-p469-kv .k{opacity:.7;font-size:12px}
        .vsp-p469-kv .v{font-weight:700;font-size:12px}
        .vsp-p469-msg{margin-top:6px;opacity:.8}
      `;
      document.head.appendChild(st);
    }

    function closestBlock(el){
      if(!el) return null;
      var cur = el;
      for(var i=0;i<12 && cur; i++){
        if(cur.classList && (cur.classList.contains("card") || cur.classList.contains("vsp-card"))) return cur;
        if(cur.tagName && /SECTION|ARTICLE|DIV/.test(cur.tagName)) {
          // heuristic: a "block" that contains Scan / Start Run
          var t = (cur.innerText||"");
          if(t.includes("Scan / Start Run") && t.includes("Kick off via")) return cur;
        }
        cur = cur.parentElement;
      }
      return el;
    }

    function findScanBlock(){
      // Find element whose text includes scan header
      var cand = qa("div,section,article").find(function(n){
        try{
          var t=(n.innerText||"");
          return t.includes("Scan / Start Run") && t.includes("Kick off via");
        }catch(e){ return false; }
      });
      return closestBlock(cand);
    }

    function beautifyScan(){
      try{
        injectCSS();
        var blk = findScanBlock();
        if(!blk) return false;
        if(blk.getAttribute("data-vsp-p469-scan")==="1") return true;

        // wrap scan block into our card container but KEEP its content
        blk.setAttribute("data-vsp-p469-scan","1");
        blk.classList.add("vsp-p469-scan-card");

        // try to create a consistent header
        var head = document.createElement("div");
        head.className = "vsp-p469-scan-head";
        head.innerHTML = `
          <div class="vsp-p469-scan-title">
            <span class="vsp-p469-dot"></span>
            <div>
              <div>Scan / Start Run</div>
              <div class="vsp-p469-sub">commercial polish • layout-safe</div>
            </div>
          </div>
          <div class="vsp-p469-row">
            <span class="vsp-p469-pill" id="p469_scan_rid_pill">RID: (none)</span>
          </div>
        `;

        // remove existing duplicate title line if exists (soft)
        // put head at top
        blk.insertBefore(head, blk.firstChild);

        // collect form controls inside blk
        var inputs = qa("input", blk).filter(function(x){
          var type=(x.getAttribute("type")||"text").toLowerCase();
          return type==="text" || type==="" || type==="search";
        });
        var selects = qa("select", blk);
        var buttons = qa("button", blk);

        // tag controls with our class for style
        inputs.forEach(function(i){ i.classList.add("vsp-p469-in"); i.style.flex="1"; });
        selects.forEach(function(s){ s.classList.add("vsp-p469-in"); });
        buttons.forEach(function(b){ b.classList.add("vsp-p469-btn"); });

        // identify likely fields
        var target = inputs[0] || null;
        var note   = inputs[1] || null;
        var mode   = selects[0] || null;

        // identify buttons by label
        var startBtn = buttons.find(function(b){ return (b.innerText||"").trim().toLowerCase().includes("start"); }) || null;
        var refBtn   = buttons.find(function(b){ return (b.innerText||"").trim().toLowerCase().includes("refresh"); }) || null;

        // build our layout rows
        var row1 = document.createElement("div");
        row1.className="vsp-p469-row";
        row1.style.marginTop="8px";

        var row2 = document.createElement("div");
        row2.className="vsp-p469-row";
        row2.style.marginTop="8px";

        // move nodes into layout (only if found)
        if(target){
          target.style.minWidth="320px";
          row1.appendChild(target);
        }
        if(mode){
          mode.style.minWidth="220px";
          row1.appendChild(mode);
        }
        if(note){
          note.style.minWidth="320px";
          note.style.flex="1";
          row2.appendChild(note);
        }
        if(startBtn) row2.appendChild(startBtn);
        if(refBtn) row2.appendChild(refBtn);

        // insert rows near top (after header)
        blk.insertBefore(row2, head.nextSibling);
        blk.insertBefore(row1, row2);

        // status area: try to find existing status table/lines (state/progress/updated)
        // We won't rely on exact DOM; just keep the remaining text, and wrap last part.
        var statusBox = document.createElement("div");
        statusBox.className="vsp-p469-statusbox";
        statusBox.innerHTML = `
          <div class="vsp-p469-kv">
            <div><div class="k">state</div><div class="v" id="p469_st_state">-</div></div>
            <div><div class="k">progress</div><div class="v" id="p469_st_prog">-</div></div>
            <div><div class="k">updated</div><div class="v" id="p469_st_upd">-</div></div>
          </div>
          <div class="vsp-p469-msg" id="p469_st_msg">Ready.</div>
        `;
        blk.appendChild(statusBox);

        // try to extract RID pill from any text "RID:" in block
        var t = (blk.innerText||"");
        var m = t.match(/RID:\s*([A-Za-z0-9_\-]+)/);
        if(m && q("#p469_scan_rid_pill", blk)) q("#p469_scan_rid_pill", blk).textContent = "RID: " + m[1];

        log("scan polished");
        return true;
      }catch(e){
        warn("scan polish failed", e);
        return false;
      }
    }

    function hideOldDuplicates(){
      // keep this minimal: hide the older “small legacy runs list” that may still appear at bottom
      // (we only hide blocks containing the old signature line)
      var sig = "Filter by RID / label / date (client-side)";
      var hidden = 0;
      qa("div,section,article").forEach(function(n){
        try{
          var t=(n.innerText||"");
          if(t.includes(sig)){
            n.style.display="none";
            hidden++;
          }
        }catch(e){}
      });
      if(hidden) log("legacy duplicates hidden:", hidden);
    }

    function applyAll(){
      hideOldDuplicates();
      beautifyScan();
    }

    onReady(function(){
      applyAll();

      // re-apply if something re-renders
      var mo = new MutationObserver(function(){
        try{ applyAll(); }catch(e){}
      });
      mo.observe(document.documentElement, {subtree:true, childList:true});
      log("observer on");
    });

  }catch(e){
    try{ console.error("[P469] init error", e); }catch(_){}
  }
})();
;/* ===================== /VSP_P469_SCAN_POLISH_C_RUNS_V1 ===================== */
"""

if "VSP_P469_SCAN_POLISH_C_RUNS_V1" not in s:
    s = s.rstrip() + "\n\n" + addon + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended P469")
PY

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt"
else
  echo "[WARN] no systemctl; restart manually" | tee -a "$OUT/log.txt"
fi

echo "[OK] Marker check:" | tee -a "$OUT/log.txt"
grep -n "VSP_P469_SCAN_POLISH_C_RUNS_V1" -n "$F" | head -n 5 | tee -a "$OUT/log.txt"

echo "[OK] DONE. Close the /c/runs tab, reopen it, then Ctrl+Shift+R." | tee -a "$OUT/log.txt"
echo "[OK] Log: $OUT/log.txt"
