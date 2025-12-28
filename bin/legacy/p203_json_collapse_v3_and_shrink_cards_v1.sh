#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p203_${TS}"
echo "[OK] backup: ${F}.bak_p203_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P203_JSON_COLLAPSE_V3"
if marker in s:
    print("[OK] already has P203; skip append")
    raise SystemExit(0)

js = r"""
/* VSP_P203_JSON_COLLAPSE_V3 */
(function(){
  if (window.__VSP_P203_JSON_COLLAPSE_V3__) return;
  window.__VSP_P203_JSON_COLLAPSE_V3__ = true;

  function looksLikeJson(txt){
    if(!txt) return false;
    txt = (""+txt).trim();
    if(!txt) return false;
    const c0 = txt[0];
    if(c0 !== "{" && c0 !== "[") return false;
    const cN = txt[txt.length-1];
    if(cN !== "}" && cN !== "]") return false;
    if(txt[0] === "<") return false;
    if(txt.length <= 200000){
      try{ JSON.parse(txt); }catch(e){ return false; }
    }
    return true;
  }

  function countLines(txt){
    if(!txt) return 0;
    const m = (""+txt).match(/\n/g);
    return (m ? m.length : 0) + 1;
  }

  function relaxHeightAround(node){
    let el = node;
    for(let i=0;i<7 && el && el !== document.body;i++){
      const cls = (el.className||"")+"";
      if(/json|pre|panel|card|box|viewer|content|gate|summary|raw/i.test(cls) || el.tagName === "SECTION"){
        el.style.height = "auto";
        el.style.maxHeight = "none";
        el.style.minHeight = "0";
      }
      el = el.parentElement;
    }
  }

  function wrapPre(pre){
    if(!pre || pre.nodeType !== 1) return;
    if(pre.closest("details.vsp-json-details")) return;

    // không phá editor / code viewer
    if(pre.closest("textarea, .CodeMirror, .ace_editor")) return;

    const txt = pre.textContent || "";
    if(!looksLikeJson(txt)) return;

    const lines = countLines(txt);

    const details = document.createElement("details");
    details.className = "vsp-json-details";
    details.open = false;

    const summary = document.createElement("summary");
    summary.className = "vsp-json-summary";
    summary.textContent = `JSON (${lines} lines) — click to expand`;
    details.appendChild(summary);

    const parent = pre.parentNode;
    if(!parent) return;
    parent.insertBefore(details, pre);
    details.appendChild(pre);

    pre.style.maxHeight = "420px";
    pre.style.overflow = "auto";
    pre.style.marginTop = "8px";

    relaxHeightAround(details);
    details.addEventListener("toggle", ()=> relaxHeightAround(details));
  }

  function scan(root){
    const scope = root || document;
    const pres = scope.querySelectorAll ? scope.querySelectorAll("pre") : [];
    for(const pre of pres) wrapPre(pre);
  }

  function install(){
    if(!document.getElementById("vsp-json-collapse-css")){
      const st = document.createElement("style");
      st.id = "vsp-json-collapse-css";
      st.textContent = `
details.vsp-json-details{
  display:block;
  width:100%;
  border:1px solid rgba(255,255,255,0.08);
  border-radius:12px;
  padding:10px 12px;
  background: rgba(0,0,0,0.12);
}
details.vsp-json-details > summary{
  cursor:pointer;
  list-style:none;
  user-select:none;
  opacity:0.92;
  font-size:13px;
}
details.vsp-json-details > summary::-webkit-details-marker{ display:none; }
`;
      document.head.appendChild(st);
    }

    scan(document);

    // MutationObserver nhẹ (throttle) để bắt JSON render sau
    let pending = false;
    const obs = new MutationObserver(()=>{
      if(pending) return;
      pending = true;
      setTimeout(()=>{ pending=false; scan(document); }, 80);
    });
    obs.observe(document.body, {childList:true, subtree:true});
    window.__VSP_JSON_COLLAPSE_OBSERVER__ = obs;

    console.log("[VSP] installed P203 (json collapse v3 + shrink cards)");
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", install);
  } else {
    install();
  }
})();
"""
p.write_text(s + "\n\n" + js + "\n", encoding="utf-8")
print("[OK] appended P203 into", p)
PY

echo "== [CHECK] node --check =="
node --check "$F"
echo "[OK] JS syntax OK"

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
