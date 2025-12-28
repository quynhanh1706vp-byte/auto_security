#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || { echo "[ERR] missing: node (need node for syntax check)"; exit 2; }

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p202_before_${TS}"
echo "[OK] backup current => ${F}.bak_p202_before_${TS}"

# Pick newest backup that passes node --check
pick=""
for b in $(ls -1t ${F}.bak_* 2>/dev/null || true); do
  tmp="/tmp/vsp_c_common_pick_$$.js"
  cp -f "$b" "$tmp"
  if node --check "$tmp" >/dev/null 2>&1; then
    pick="$b"
    rm -f "$tmp"
    break
  fi
  rm -f "$tmp"
done

if [ -z "$pick" ]; then
  echo "[ERR] no syntax-ok backup found (${F}.bak_*)"
  echo "      You can list backups: ls -lt ${F}.bak_* | head"
  exit 2
fi

cp -f "$pick" "$F"
echo "[OK] restored base from: $pick"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P202_JSON_COLLAPSE_V2" in s:
    print("[OK] P202 already installed")
    raise SystemExit(0)

patch = r"""
/* VSP_P202_JSON_COLLAPSE_V2
 * Goal: collapse ALL JSON <pre>/<textarea> on /c/settings + /c/rule_overrides
 * Safe: idempotent, works with dynamic render (MutationObserver)
 */
(function(){
  try{
    const PATH = (location && location.pathname) ? location.pathname : "";
    const enabled = (PATH.indexOf("/c/settings")>=0) || (PATH.indexOf("/c/rule_overrides")>=0);
    if(!enabled) return;

    function injectStyle(){
      if(document.getElementById("vsp_json_collapse_style_v2")) return;
      const st = document.createElement("style");
      st.id = "vsp_json_collapse_style_v2";
      st.textContent = [
        "details.vsp-json-details{background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.08);border-radius:12px;padding:8px 10px;margin:10px 0;}",
        "details.vsp-json-details summary{cursor:pointer;color:rgba(255,255,255,0.78);font-weight:700;outline:none;list-style:none;}",
        "details.vsp-json-details summary::-webkit-details-marker{display:none;}",
        "details.vsp-json-details[open] summary{color:rgba(255,255,255,0.92);}",
        ".vsp-json-details-body{padding-top:8px;}",
        ".vsp-json-details-body pre{margin:0;max-height:60vh;overflow:auto;white-space:pre;}",
        ".vsp-json-details-body textarea{width:100%;height:60vh;overflow:auto;}"
      ].join("\n");
      document.head.appendChild(st);
    }

    function isJsonLike(txt){
      const t = (txt||"").trim();
      if(!t) return false;
      const a = t[0], b = t[t.length-1];
      return (a==="{" && b==="}") || (a==="[" && b==="]");
    }

    function getText(el){
      if(!el) return "";
      if(typeof el.value === "string") return el.value;
      return el.textContent || "";
    }

    function collapseOne(el){
      if(!el || !el.parentNode) return;
      if(el.closest && el.closest("details.vsp-json-details")) return;

      const txt = getText(el);
      if(!isJsonLike(txt)) return;

      const lines = txt.split("\n").length;
      const chars = txt.length;
      if(chars < 500 && lines < 12) return;

      const details = document.createElement("details");
      details.className = "vsp-json-details";
      details.open = false;

      const summary = document.createElement("summary");
      summary.textContent = "JSON ("+lines+" lines) — click to expand";
      details.appendChild(summary);

      const body = document.createElement("div");
      body.className = "vsp-json-details-body";
      details.appendChild(body);

      const parent = el.parentNode;
      parent.replaceChild(details, el);
      body.appendChild(el);

      // make sure it stays readable
      try{
        if(el.tagName && el.tagName.toLowerCase()==="pre"){
          el.style.margin = "0";
          el.style.overflow = "auto";
          el.style.maxHeight = "60vh";
        }else if(el.tagName && el.tagName.toLowerCase()==="textarea"){
          el.style.fontFamily = 'ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace';
        }
      }catch(_e){}
    }

    function sweep(root){
      if(!root || !root.querySelectorAll) return;
      const els = root.querySelectorAll("pre, textarea");
      for(const el of els) collapseOne(el);
    }

    function boot(){
      injectStyle();
      sweep(document);
      // Observe dynamic rendering
      let t = null;
      const obs = new MutationObserver(function(){
        if(t) return;
        t = setTimeout(function(){
          t = null;
          sweep(document);
        }, 120);
      });
      obs.observe(document.body, {subtree:true, childList:true});
      console.log("[VSP] installed P202 (JSON collapse v2)");
    }

    if(document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", boot);
    }else{
      boot();
    }
  }catch(e){
    try{ console.warn("[VSP] P202 failed", e); }catch(_e){}
  }
})();
"""
p.write_text(s + "\n\n" + patch, encoding="utf-8")
print("[OK] appended P202 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
node --check "$F"
echo "[OK] JS syntax OK"

echo ""
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
