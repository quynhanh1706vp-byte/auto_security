#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p200_before_${TS}"
echo "[OK] backup current => ${F}.bak_p200_before_${TS}"

# Try to restore a known-good base (p127b) to stop "patch stacking"
BASE_BAK="$(ls -1 static/js/vsp_c_common_v1.js.bak_p127b_* 2>/dev/null | sort | tail -n 1 || true)"
if [ -n "${BASE_BAK}" ]; then
  cp -f "${BASE_BAK}" "$F"
  echo "[OK] restored base from: ${BASE_BAK}"
else
  echo "[WARN] no bak_p127b found; keep current file and just apply P200 safely"
fi

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P200_JSON_COLLAPSE_UNIFIED_V1" in s:
    print("[OK] P200 already installed")
    raise SystemExit(0)

patch = r"""
/* VSP_P200_JSON_COLLAPSE_UNIFIED_V1
   Goal: collapse ALL large JSON blocks on /c/settings + /c/rule_overrides (and any tab),
   safely: close existing JSON <details>, and wrap large JSON <pre>/<textarea>/<code> into <details>.
*/
(function(){
  "use strict";
  const TAG="P200";

  const isJsonish=(txt)=>{
    try{
      if(!txt) return false;
      const t=String(txt).trim();
      if(t.length<2) return false;
      const c0=t[0];
      if(c0!=="{" && c0!=="[") return false;
      // crude signals of JSON
      if(!/\"[^\"]+\"\s*:/.test(t) && !/[\{\[]\s*\"/.test(t)) return false;
      return true;
    }catch(_){ return false; }
  };

  const countLines=(txt)=>{
    try{
      const m=String(txt).match(/\n/g);
      return (m?m.length:0)+1;
    }catch(_){ return 1; }
  };

  const injectCss=()=>{
    try{
      if(document.getElementById("vsp-json-collapse-css")) return;
      const style=document.createElement("style");
      style.id="vsp-json-collapse-css";
      style.textContent=`
        details.vsp-json-details { margin: 6px 0; border-radius: 10px; background: rgba(255,255,255,0.04); padding: 6px 10px; }
        details.vsp-json-details > summary { cursor:pointer; user-select:none; font-size: 12px; opacity: .85; }
        details.vsp-json-details[open] > summary { opacity: 1; }
        details.vsp-json-details pre, details.vsp-json-details textarea, details.vsp-json-details code { margin-top: 8px; }
      `;
      (document.head||document.documentElement).appendChild(style);
    }catch(_){}
  };

  const closeExistingJsonDetails=()=>{
    try{
      document.querySelectorAll("details").forEach(d=>{
        try{
          const sum=d.querySelector("summary");
          const st=sum ? (sum.textContent||"") : "";
          if(/json/i.test(st)) d.open=false;
        }catch(_){}
      });
    }catch(_){}
  };

  const wrapNode=(el)=>{
    try{
      if(!el || !el.parentNode) return;
      if(el.closest("details.vsp-json-details")) return;

      const tag=(el.tagName||"").toUpperCase();
      const txt = (tag==="TEXTAREA") ? (el.value||"") : (el.textContent||"");
      if(!txt || txt.length < 200) return;
      if(!isJsonish(txt)) return;

      // avoid double-wrapping CODE inside PRE
      if(tag==="CODE" && el.closest("pre")) return;

      const details=document.createElement("details");
      details.className="vsp-json-details";
      details.open=false;

      const summary=document.createElement("summary");
      const n=countLines(txt);
      summary.textContent = `JSON (${n} lines) — click to expand`;
      details.appendChild(summary);

      // replace el by details and move el inside
      const parent=el.parentNode;
      parent.replaceChild(details, el);
      details.appendChild(el);

      // sane display
      try{
        el.style.overflow="auto";
        el.style.maxHeight="60vh";
        if(tag==="TEXTAREA") el.style.width="100%";
      }catch(_){}
    }catch(_){}
  };

  const applyOnce=()=>{
    try{
      injectCss();
      closeExistingJsonDetails();

      const nodes = Array.from(document.querySelectorAll("pre, textarea, code"));
      // cap to avoid heavy loops in big pages
      const max = Math.min(nodes.length, 200);
      for(let i=0;i<max;i++){
        wrapNode(nodes[i]);
      }
    }catch(_){}
  };

  // schedule/throttle
  let last=0, pending=false;
  const schedule=()=>{
    const now=Date.now();
    if(pending) return;
    if(now-last < 120) return;
    pending=true;
    last=now;
    requestAnimationFrame(()=>{
      pending=false;
      applyOnce();
    });
  };

  // initial
  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", schedule, {once:true});
  } else {
    schedule();
  }

  // observe late-rendered JSON
  try{
    const obs=new MutationObserver(()=>schedule());
    obs.observe(document.documentElement || document.body, {childList:true, subtree:true});
  }catch(_){}

  // extra retries (fetch updates)
  try{
    let c=0;
    const iv=setInterval(()=>{
      schedule();
      c++;
      if(c>=12) clearInterval(iv);
    }, 700);
  }catch(_){}

  try{ console.log("[VSP] installed P200 (json collapse unified)"); }catch(_){}
})();
 /* END VSP_P200_JSON_COLLAPSE_UNIFIED_V1 */
"""

p.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended P200 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
if command -v node >/dev/null 2>&1; then
  node --check "$F"
  echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skipped syntax check"
fi

echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
