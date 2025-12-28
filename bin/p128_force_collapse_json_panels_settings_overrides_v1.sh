#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p128_${TS}"
echo "[OK] backup: ${F}.bak_p128_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P128_FORCE_COLLAPSE_JSON_PANELS"
if MARK in s:
    print("[OK] P128 already present")
    raise SystemExit(0)

addon = r"""
// VSP_P128_FORCE_COLLAPSE_JSON_PANELS
(function(){
  try{
    const MARK = "VSP_P128_FORCE_COLLAPSE_JSON_PANELS";

    function inTargetTabs(){
      const path = (location.pathname || "");
      return /(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(path);
    }

    function looksLikeJson(txt){
      if(!txt) return false;
      const t = String(txt).trim();
      if(!t) return false;
      // Accept "startsWith { or [" even if not endsWith (sometimes truncated)
      return (t.startsWith("{") || t.startsWith("["));
    }

    function wrapPreIntoDetails(pre, label){
      if(!pre || pre.__vsp_p128_wrapped) return false;
      const txt = (pre.textContent || "").trim();
      if(!looksLikeJson(txt)) return false;

      // avoid double wrap
      if(pre.closest("details")) { pre.__vsp_p128_wrapped = true; return false; }

      const details = document.createElement("details");
      details.className = "vsp-details vsp-details--json";
      details.open = false;

      const sum = document.createElement("summary");
      sum.textContent = label || "Raw JSON (click to expand)";
      details.appendChild(sum);

      const holder = document.createElement("div");
      holder.style.maxHeight = "320px";
      holder.style.overflow = "auto";

      // Move original <pre> into holder, then replace it with <details>
      const parent = pre.parentNode;
      if(!parent) return false;

      parent.replaceChild(details, pre);
      holder.appendChild(pre);
      details.appendChild(holder);

      pre.__vsp_p128_wrapped = true;
      return true;
    }

    function collapseJsonPanels(){
      if(!inTargetTabs()) return;

      // Collapse all JSON-ish <pre>
      const pres = Array.from(document.querySelectorAll("pre"));
      for(const pre of pres){
        const txt = (pre.textContent || "").trim();
        if(!txt) continue;

        let label = "Raw JSON (click to expand)";
        const ctx = (pre.parentElement && pre.parentElement.textContent) ? pre.parentElement.textContent : "";
        if(/live\s+from/i.test(ctx) || /\/api\/vsp\//i.test(ctx)) label = "Live JSON (debug) — click to expand";

        wrapPreIntoDetails(pre, label);
      }

      // Extra: sometimes raw JSON is inside a big <div> (no <pre>) -> convert & wrap
      const bigBlocks = Array.from(document.querySelectorAll("div"));
      for(const b of bigBlocks){
        if(b.querySelector("pre,details")) continue;
        const t = (b.textContent || "").trim();
        if(t.length < 400) continue;
        if(!looksLikeJson(t)) continue;

        const pre = document.createElement("pre");
        pre.textContent = t;
        b.textContent = "";
        b.appendChild(pre);
        wrapPreIntoDetails(pre, "Raw JSON (click to expand)");
      }
    }

    function installObserver(){
      if(!inTargetTabs()) return;
      const root = document.documentElement || document.body;
      if(!root) return;

      const mo = new MutationObserver(() => { try{ collapseJsonPanels(); }catch(_){ } });
      mo.observe(root, { subtree:true, childList:true });

      // delayed passes for late-render
      let n = 0;
      const iv = setInterval(() => {
        n++;
        try{ collapseJsonPanels(); }catch(_){ }
        if(n >= 12) clearInterval(iv);
      }, 400);
    }

    // Silence noisy AbortError in console (doesn't hide real errors)
    window.addEventListener("unhandledrejection", function(ev){
      try{
        const r = ev && ev.reason;
        const name = r && r.name;
        const msg = (r && r.message) ? String(r.message) : "";
        if(name === "AbortError" || /aborted/i.test(msg)){
          ev.preventDefault();
        }
      }catch(_){}
    });

    // run now + after DOM ready
    try{ collapseJsonPanels(); installObserver(); }catch(_){}
    document.addEventListener("DOMContentLoaded", function(){
      try{ collapseJsonPanels(); installObserver(); }catch(_){}
    });

    console.log("[VSPC] installed P128");
  }catch(_){}
})();
"""
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P128 into", p)
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F" && echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found, skipped syntax check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
