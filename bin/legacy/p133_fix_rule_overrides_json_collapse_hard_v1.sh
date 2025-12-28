#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p133_${TS}"
echo "[OK] backup: ${F}.bak_p133_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# If previous broken split token exists, fix it defensively
s = s.replace('txt.split("\n"\n).length', 'txt.split("\\n").length')
s = s.replace('txt.split("\n"\r).length', 'txt.split("\\n").length')
s = s.replace('txt.split("\n"\r\n).length', 'txt.split("\\n").length')

# Remove any previously appended duplicate blocks of our own markers if they exist (safe)
s = re.sub(r"/\*\s*VSP_P133_JSON_COLLAPSE_HARD_V1_BEGIN\s*\*/.*?/\*\s*VSP_P133_JSON_COLLAPSE_HARD_V1_END\s*\*/\s*",
           "", s, flags=re.S)

if "VSP_P133_JSON_COLLAPSE_HARD_V1_BEGIN" in s:
    # already removed above, but keep guard
    pass

inject = r"""
/* VSP_P133_JSON_COLLAPSE_HARD_V1_BEGIN */
/**
 * Goal: On /c/settings + /c/rule_overrides, any long JSON-looking block should be collapsed by default.
 * Works for: <pre>, <code>, <textarea>, and "container divs" that look like JSON dumps.
 * Uses MutationObserver to catch late renders.
 */
(function(){
  try{
    const PATH = String(location.pathname || "");
    const isSettings = /(?:^|\/)c\/settings(?:$)/.test(PATH);
    const isOverrides = /(?:^|\/)c\/rule_overrides(?:$)/.test(PATH);
    if (!isSettings && !isOverrides) return;

    function looksJsonText(txt){
      if (!txt) return false;
      const t = String(txt).trim();
      if (!t) return false;
      // quick JSON-ish shape
      const a = t[0], b = t[t.length-1];
      if (!((a === "{" && b === "}") || (a === "[" && b === "]"))) return false;
      // avoid tiny objects
      if (t.length < 200) return false;
      return true;
    }

    function lineCount(txt){
      // robust for \n or \r\n
      return String(txt).split(/\r?\n/).length;
    }

    function wrapIntoDetails(el, label){
      if (!el || !el.parentElement) return false;
      if (el.closest("details.vsp-details")) return false;

      const txt = (el.textContent || el.value || "").trim();
      const lines = lineCount(txt);

      const details = document.createElement("details");
      details.className = "vsp-details";
      details.open = false;

      const sum = document.createElement("summary");
      sum.textContent = label || "Raw JSON (click to expand)";
      details.appendChild(sum);

      // keep element but constrain height when expanded
      const holder = document.createElement("div");
      holder.style.maxHeight = "420px";
      holder.style.overflow = "auto";
      holder.style.borderRadius = "12px";

      // For textarea, keep read-only look
      try{
        if (el.tagName === "TEXTAREA"){
          el.style.width = "100%";
          el.style.minHeight = "240px";
        }else{
          el.style.maxHeight = "unset";
          el.style.overflow = "visible";
          el.style.whiteSpace = "pre";
        }
      }catch(e){}

      holder.appendChild(el);

      const parent = details;
      parent.appendChild(holder);

      // replace in DOM
      const ph = document.createElement("div");
      ph.className = "vsp-json-collapsed";
      el.parentElement.replaceChild(ph, el);
      ph.appendChild(parent);

      // make summary informative
      try{
        sum.textContent = (label || "Raw JSON") + ` (lines=${lines})`;
      }catch(e){}
      return true;
    }

    function scanAndCollapse(root){
      root = root || document;

      // 1) pre/code/textarea first
      const candidates = Array.from(root.querySelectorAll("pre, code, textarea"));
      for (const el of candidates){
        try{
          const txt = (el.tagName === "TEXTAREA") ? (el.value || "") : (el.textContent || "");
          const t = String(txt).trim();
          if (!looksJsonText(t)) continue;

          // Settings can be longer; Overrides often shorter but still annoying
          const minLines = isOverrides ? 8 : 30;
          if (lineCount(t) < minLines) continue;

          wrapIntoDetails(el, "Raw JSON");
        }catch(e){}
      }

      // 2) fallback: container divs that are pure JSON dumps (some templates render JSON into <div>)
      const divs = Array.from(root.querySelectorAll("div"));
      for (const d of divs){
        try{
          // skip if it contains interactive controls / tables
          if (d.querySelector("button, input, select, textarea, table")) continue;

          const txt = (d.textContent || "").trim();
          if (!looksJsonText(txt)) continue;

          const minLines = isOverrides ? 8 : 30;
          if (lineCount(txt) < minLines) continue;

          // convert div to pre for better formatting then collapse
          const pre = document.createElement("pre");
          pre.textContent = txt;
          pre.style.margin = "0";
          d.replaceWith(pre);
          wrapIntoDetails(pre, "Raw JSON");
        }catch(e){}
      }

      // 3) Overrides page: aggressively collapse the "live from /api/vsp/rule_overrides" top dump if still present
      if (isOverrides){
        try{
          const all = Array.from(document.querySelectorAll("*"));
          for (const node of all){
            const t = (node.textContent || "").trim();
            if (!t) continue;
            if (t.includes("Rule Overrides (live from") || t.includes("rule_overrides")){
              // find nearby pre/textarea/code and collapse them
              const box = node.closest("section, div") || node.parentElement;
              if (!box) continue;
              const near = box.querySelector("pre, textarea, code, div");
              if (near){
                // scan only this box (faster)
                scanAndCollapse(box);
              }
            }
          }
        }catch(e){}
      }
    }

    // Run now + delayed (late DOM)
    scanAndCollapse(document);
    setTimeout(()=>scanAndCollapse(document), 300);
    setTimeout(()=>scanAndCollapse(document), 1200);

    // Observe changes (late render / rerender)
    let pending = false;
    const obs = new MutationObserver((_muts)=>{
      if (pending) return;
      pending = true;
      requestAnimationFrame(()=>{
        pending = false;
        scanAndCollapse(document);
      });
    });
    obs.observe(document.documentElement, {subtree:true, childList:true});

    console.log("[VSP] installed P133 (hard JSON collapse)");
  }catch(e){
    console.warn("[VSP] P133 failed", e);
  }
})();
 /* VSP_P133_JSON_COLLAPSE_HARD_V1_END */
"""

# Append at end (safer than trying to insert into unknown function blocks)
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended P133 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
if command -v node >/dev/null 2>&1; then
  node --check "$F"
  echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found, skipped syntax check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/rule_overrides"
echo "  http://127.0.0.1:8910/c/settings"
