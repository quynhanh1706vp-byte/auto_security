#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v node >/dev/null 2>&1 || { echo "[WARN] node not found -> skip node --check"; }

JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2_5_fixsyntax_${TS}"
echo "[BACKUP] ${JS}.bak_p2_5_fixsyntax_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

BEGIN = "/* ===================== VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */"
END   = "/* ===================== /VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */"

if BEGIN not in s or END not in s:
    print("[ERR] marker block not found. BEGIN/END missing.", file=sys.stderr)
    sys.exit(2)

# Clean, valid JS replacement block
PATCH = r"""/* ===================== VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */
(function(){
  try{
    var params = new URLSearchParams(window.location.search || "");
    var rid = params.get("rid");
    if(!rid) return;

    function attrSafe(v){
      // safe string for simple attribute compare (not CSS selector)
      return String(v == null ? "" : v).trim();
    }

    function injectStyle(){
      if(document.getElementById("vsp_runs_rid_hl_style")) return;
      var st = document.createElement("style");
      st.id = "vsp_runs_rid_hl_style";
      st.textContent = [
        ".vsp-rid-hl{outline:2px solid rgba(255,255,255,0.20);box-shadow:0 0 0 2px rgba(80,160,255,0.35) inset;border-radius:10px;}",
        ".vsp-rid-hl td,.vsp-rid-hl .cell,.vsp-rid-hl .col{background:rgba(80,160,255,0.12)!important;}",
        ".vsp-rid-pill{display:inline-block;margin-left:8px;padding:2px 8px;border-radius:999px;font-size:12px;background:rgba(80,160,255,0.18);border:1px solid rgba(80,160,255,0.35);}"
      ].join("\n");
      (document.head || document.documentElement).appendChild(st);
    }

    function setFilterInput(){
      var selectors = [
        "input#runsFilter",
        "input[name='runsFilter']",
        "input[type='search']",
        "input[name='filter']",
        "input[placeholder*='RID']",
        "input[placeholder*='rid']",
        "input[placeholder*='filter']",
        "input[placeholder*='search']"
      ];
      for(var i=0;i<selectors.length;i++){
        var el = document.querySelector(selectors[i]);
        if(el){
          el.value = rid;
          try{ el.dispatchEvent(new Event("input", {bubbles:true})); }catch(e){}
          try{ el.dispatchEvent(new Event("change", {bubbles:true})); }catch(e){}
          return true;
        }
      }
      return false;
    }

    function elMatchesRid(el){
      if(!el) return false;
      try{
        var v1 = el.getAttribute && el.getAttribute("data-rid");
        var v2 = el.getAttribute && el.getAttribute("data-runid");
        var v3 = el.getAttribute && el.getAttribute("data-run-id");
        if(attrSafe(v1) === rid || attrSafe(v2) === rid || attrSafe(v3) === rid) return true;
      }catch(e){}
      try{
        var t = (el.textContent || "");
        if(t.indexOf(rid) >= 0) return true;
      }catch(e){}
      return false;
    }

    function findRow(){
      // 1) data-* attributes
      var nodes = document.querySelectorAll("[data-rid],[data-runid],[data-run-id]");
      for(var i=0;i<nodes.length;i++){
        if(elMatchesRid(nodes[i])){
          return (nodes[i].closest && nodes[i].closest("tr, .run-row, .vsp-run-row, li, .card, .row")) || nodes[i];
        }
      }

      // 2) scan table rows by text
      var trs = document.querySelectorAll("tr");
      for(var j=0;j<trs.length;j++){
        if(elMatchesRid(trs[j])) return trs[j];
      }

      // 3) scan common list items/cards
      var items = document.querySelectorAll(".run-row,.vsp-run-row,li,.card,.row");
      for(var k=0;k<items.length;k++){
        if(elMatchesRid(items[k])) return items[k];
      }
      return null;
    }

    function hideNonMatchingInSameParent(row){
      var parent = row && row.parentElement;
      if(!parent) return;
      var kids = parent.children ? Array.prototype.slice.call(parent.children) : [];
      if(kids.length <= 1) return;

      for(var i=0;i<kids.length;i++){
        var el = kids[i];
        if(el === row){ el.style.display = ""; continue; }

        // keep header rows (table)
        var tag = (el.tagName || "").toLowerCase();
        if(tag === "thead"){ el.style.display = ""; continue; }
        if(tag === "tr"){
          var hasTH = false;
          try{ hasTH = !!el.querySelector("th"); }catch(e){}
          if(hasTH){ el.style.display = ""; continue; }
        }

        if(elMatchesRid(el)){ el.style.display = ""; continue; }
        el.style.display = "none";
      }
    }

    function highlight(row){
      injectStyle();
      try{ row.classList.add("vsp-rid-hl"); }catch(e){}
      try{
        var anchor = row.querySelector ? (row.querySelector("td, .rid, .run-id, .id") || row) : row;
        if(anchor && !(anchor.querySelector && anchor.querySelector(".vsp-rid-pill"))){
          var pill = document.createElement("span");
          pill.className = "vsp-rid-pill";
          pill.textContent = "RID filter";
          anchor.appendChild(pill);
        }
      }catch(e){}
    }

    function scrollToRow(row){
      try{ row.scrollIntoView({block:"center"}); }
      catch(e){ try{ row.scrollIntoView(true); }catch(_){} }
    }

    function autoOpenOverlay(row){
      // best-effort: click first action/report/overlay button/link in the row
      if(!row || !row.querySelector) return false;
      var sel = [
        "button[data-action*='overlay']",
        "button[data-action*='report']",
        "a[data-action*='overlay']",
        "a[data-action*='report']",
        "button[title*='Actions']",
        "button[title*='Report']",
        "a[title*='Actions']",
        "a[title*='Report']"
      ].join(",");
      var btn = row.querySelector(sel);
      if(btn){ try{ btn.click(); return true; }catch(e){} }
      return false;
    }

    // kick
    setFilterInput();

    var startedAt = Date.now();
    var maxMs = 15000;
    var timer = setInterval(function(){
      var row = findRow();
      if(row){
        highlight(row);
        hideNonMatchingInSameParent(row);
        scrollToRow(row);

        var open = params.get("open");
        if(open === "1" || open === "true") autoOpenOverlay(row);

        clearInterval(timer);
        return;
      }
      if(Date.now() - startedAt > maxMs){
        clearInterval(timer);
        try{ console.warn("[VSP P2.5] RID not found in runs list:", rid); }catch(e){}
      }
    }, 300);

  }catch(e){
    try{ console.warn("[VSP P2.5] failed:", e); }catch(_) {}
  }
})();
/* ===================== /VSP_P2_5_RUNS_AUTOFILTER_RID_V1 ===================== */"""

# replace whole block (including begin/end)
block_re = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END), re.DOTALL)
s2, n = block_re.subn(PATCH, s, count=1)
if n != 1:
    print(f"[ERR] failed to replace marker block (n={n})", file=sys.stderr)
    sys.exit(2)

p.write_text(s2, encoding="utf-8")
print("[OK] replaced marker block with clean JS")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
  echo "[OK] node --check: $JS"
fi

echo
echo "[NEXT] Test:"
echo "  1) Ctrl+Shift+R /runs?rid=VSP_CI_...  -> highlight + scroll + only that RID visible"
echo "  2) Optional: /runs?rid=VSP_CI_...&open=1  -> try auto-open overlay"
