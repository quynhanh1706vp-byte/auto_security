#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p204_${TS}"
echo "[OK] backup: ${F}.bak_p204_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P204_JSON_COLLAPSE_FINAL_V1"
if MARK in s:
    print("[OK] P204 already present (skip)")
    raise SystemExit(0)

addon = r"""
/* ===== VSP_P204_JSON_COLLAPSE_FINAL_V1 =====
   Robust JSON PRE collapse for /c/settings and /c/rule_overrides
   - Wrap JSON-ish <pre> into <details><summary>JSON (N lines) ...</summary><pre>...</pre></details>
   - Re-applies on dynamic re-render via MutationObserver (debounced)
   - Idempotent and safe (does not hide whole panels/cards)
*/
(function(){
  try{
    if (window.__VSP_P204_JSON_COLLAPSE_FINAL_V1__) return;
    window.__VSP_P204_JSON_COLLAPSE_FINAL_V1__ = true;

    function isTargetPage(){
      const p = (location && location.pathname) ? location.pathname : "";
      return (p === "/c/settings" || p === "/c/rule_overrides");
    }

    function looksJson(txt){
      if (!txt) return false;
      const t = (""+txt).trim();
      if (!t) return false;
      const c0 = t[0];
      if (c0 !== "{" && c0 !== "[") return false;
      // avoid collapsing tiny non-json pre blocks accidentally
      return (t.length >= 2);
    }

    function countLines(txt){
      if (!txt) return 0;
      // normalize CRLF
      const t = (""+txt).replace(/\r\n/g, "\n").replace(/\r/g, "\n");
      // count newline + 1 (unless empty)
      return t.length ? (t.split("\n").length) : 0;
    }

    function ensureStyle(){
      if (document.getElementById("vsp_json_collapse_style_p204")) return;
      const st = document.createElement("style");
      st.id = "vsp_json_collapse_style_p204";
      st.textContent = `
        details.vsp-json-details{
          margin: 8px 0;
          padding: 8px 10px;
          border: 1px solid rgba(255,255,255,0.08);
          border-radius: 12px;
          background: rgba(255,255,255,0.02);
        }
        details.vsp-json-details > summary{
          cursor: pointer;
          user-select: none;
          font-size: 12px;
          letter-spacing: .2px;
          opacity: .9;
          outline: none;
          list-style: none;
        }
        details.vsp-json-details > summary::-webkit-details-marker{ display:none; }
        details.vsp-json-details[open] > summary{ margin-bottom: 8px; opacity: 1; }
        details.vsp-json-details pre{
          margin: 0;
          padding: 10px;
          border-radius: 10px;
          overflow: auto;
          max-height: 420px;
        }
      `;
      document.head.appendChild(st);
    }

    function updateSummary(details, pre){
      try{
        const sum = details.querySelector(":scope > summary");
        const txt = pre ? (pre.textContent || "") : "";
        const n = countLines(txt);
        if (sum) sum.textContent = "JSON (" + n + " lines) — click to expand";
      }catch(_e){}
    }

    function wrapPre(pre){
      if (!pre || pre.nodeType !== 1) return;
      if (!isTargetPage()) return;

      // skip if already wrapped
      const existing = pre.closest("details.vsp-json-details");
      if (existing){
        updateSummary(existing, pre);
        return;
      }

      // allow opt-out
      if (pre.closest(".vsp-no-json-collapse,[data-no-json-collapse='1']")) return;

      const txt = pre.textContent || "";
      if (!looksJson(txt)) return;

      ensureStyle();

      const details = document.createElement("details");
      details.className = "vsp-json-details";
      details.open = false;

      const summary = document.createElement("summary");
      details.appendChild(summary);

      // insert details before pre, then move pre into details
      const parent = pre.parentNode;
      if (!parent) return;
      parent.insertBefore(details, pre);
      details.appendChild(pre);

      updateSummary(details, pre);
    }

    function apply(root){
      if (!isTargetPage()) return;
      root = root || document;

      // collapse all JSON-ish <pre> on those tabs
      const pres = root.querySelectorAll("pre");
      pres.forEach(wrapPre);
    }

    let t = null;
    function schedule(){
      if (!isTargetPage()) return;
      if (t) clearTimeout(t);
      t = setTimeout(function(){
        try{ apply(document); }catch(_e){}
      }, 60);
    }

    // initial
    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", schedule, {once:true});
    } else {
      schedule();
    }

    // navigation events
    window.addEventListener("popstate", schedule);
    window.addEventListener("hashchange", schedule);

    // re-apply on dynamic re-render
    const obs = new MutationObserver(function(muts){
      if (!isTargetPage()) return;
      for (const m of muts){
        if (m.addedNodes && m.addedNodes.length){
          schedule();
          break;
        }
      }
    });
    obs.observe(document.documentElement || document.body, {subtree:true, childList:true});

    console.log("[VSP] installed P204 (JSON collapse final)");
  }catch(e){
    console.warn("[VSP] P204 install failed:", e);
  }
})();
"""

# append safely
s2 = s.rstrip() + "\n\n" + addon.strip() + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended P204 into vsp_c_common_v1.js")
PY

echo "== [CHECK] node --check =="
node --check "$F"
echo "[OK] JS syntax OK"

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
echo
echo "[ROLLBACK] if needed:"
echo "  cp -f ${F}.bak_p204_${TS} ${F} && node --check ${F}"
