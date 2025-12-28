#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p131_${TS}"
echo "[OK] backup: ${F}.bak_p131_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P131_HARD_HIDE_LIVE_JSON_PANELS_V1"
if MARK in s:
    print("[OK] already patched P131"); raise SystemExit(0)

addon = r"""
/* VSP_P131_HARD_HIDE_LIVE_JSON_PANELS_V1 */
(function(){
  try{
    if (window.__VSP_P131_INSTALLED__) return;
    window.__VSP_P131_INSTALLED__ = 1;

    const isTarget = /(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(location.pathname || "");
    if (!isTarget) return;

    const norm = (x)=>String(x||"").toLowerCase().replace(/\s+/g," ").trim();

    function looksLikeJsonText(txt){
      txt = String(txt||"").trim();
      if (!txt) return false;
      const a = txt[0];
      if (a !== "{" and a !== "[") return False
    }
  }catch(_){}
})();
"""

# NOTE: build addon safely in python (avoid JS 'and/or' mistakes)
addon = r"""
/* VSP_P131_HARD_HIDE_LIVE_JSON_PANELS_V1 */
(function(){
  try{
    if (window.__VSP_P131_INSTALLED__) return;
    window.__VSP_P131_INSTALLED__ = 1;

    const isTarget = /(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(location.pathname || "");
    if (!isTarget) return;

    const norm = (x)=>String(x||"").toLowerCase().replace(/\s+/g," ").trim();

    function looksLikeJsonText(txt){
      txt = String(txt||"").trim();
      if (!txt) return false;
      if (!(txt.startsWith("{") || txt.startsWith("["))) return false;
      if (txt.startsWith("{") && !txt.endsWith("}")) return false;
      if (txt.startsWith("[") && !txt.endsWith("]")) return false;
      return true;
    }

    function isEditorPanel(node){
      try{
        if (!node || !node.querySelectorAll) return false;
        const btns = Array.from(node.querySelectorAll("button,a"));
        const texts = btns.map(b=>norm(b.textContent));
        // protect editor area (LOAD/SAVE/EXPORT)
        return texts.includes("load") || texts.includes("save") || texts.includes("export");
      }catch(_){ return false; }
    }

    function findHideContainer(el){
      let cur = el;
      for (let i=0;i<10 && cur && cur!==document.body;i++){
        if (isEditorPanel(cur)) return null; // never hide editor
        if (cur.classList){
          if (cur.classList.contains("vsp-card") || cur.classList.contains("vsp-panel") ||
              cur.classList.contains("card") || cur.classList.contains("panel")) return cur;
        }
        cur = cur.parentElement;
      }
      return el && el.parentElement ? el.parentElement : el;
    }

    function hideNode(n){
      if (!n) return;
      try{
        n.setAttribute("data-vsp-hidden","p131");
        n.style.display="none";
      }catch(_){}
    }

    function sweep(){
      // 1) hide <details> "Raw JSON ..."
      for (const det of Array.from(document.querySelectorAll("details"))){
        const sum = det.querySelector("summary");
        if (!sum) continue;
        if (/raw json/.test(norm(sum.textContent))){
          const c = findHideContainer(det) || det;
          hideNode(c);
        }
      }

      // 2) hide containers that have "Open JSON" button AND a <pre> json
      for (const btn of Array.from(document.querySelectorAll("button,a"))){
        const t = norm(btn.textContent);
        if (t !== "open json") continue;
        const c = findHideContainer(btn);
        if (!c) continue;
        if (c.querySelector && c.querySelector("pre")) hideNode(c);
      }

      // 3) hide big <pre> JSON blocks (but keep editor)
      for (const pre of Array.from(document.querySelectorAll("pre"))){
        const txt = (pre.textContent || "").trim();
        if (!looksLikeJsonText(txt)) continue;
        const lines = txt.split("\n").length;
        if (lines < 5) continue;
        const c = findHideContainer(pre) || pre;
        hideNode(c);
      }

      // 4) hide "Gate summary" / "Rule Overrides (live...)" header panels if they include pre
      for (const el of Array.from(document.querySelectorAll("h1,h2,h3,h4,div,span"))){
        const t = norm(el.textContent);
        if (!(t.startsWith("gate summary") || t.startsWith("rule overrides (live"))) continue;
        const c = findHideContainer(el);
        if (c && c.querySelector && c.querySelector("pre")) hideNode(c);
      }
    }

    const safeSweep = ()=>{ try{sweep();}catch(e){ console.warn("[VSP] P131 sweep error", e); } };

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", safeSweep, {once:true});
    } else {
      safeSweep();
    }

    // observe future insertions (some pages render async)
    const mo = new MutationObserver(()=>safeSweep());
    mo.observe(document.documentElement, {childList:true, subtree:true});

    console.log("[VSP] installed P131 (hard hide live JSON panels)");
  }catch(_){}
})();
"""

p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P131 into", p)
PY

echo "== [CHECK] node --check =="
if command -v node >/dev/null 2>&1; then
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found, skipped"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
