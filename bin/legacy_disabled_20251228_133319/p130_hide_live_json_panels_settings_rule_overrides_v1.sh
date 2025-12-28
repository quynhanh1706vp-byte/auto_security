#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p130_${TS}"
echo "[OK] backup: ${F}.bak_p130_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P130_HIDE_LIVE_JSON_PANELS_V1"
if MARK in s:
    print("[OK] P130 already present")
else:
    patch = r"""
/* VSP_P130_HIDE_LIVE_JSON_PANELS_V1
 * Commercial: hide debug "live JSON" panels on /c/settings and /c/rule_overrides
 * Keep the editor panel (LOAD/SAVE/EXPORT) intact.
 */
(function(){
  if (window.__VSP_P130_INSTALLED) return;
  window.__VSP_P130_INSTALLED = true;

  const RX_PATH = /(?:^|\/)c\/(settings|rule_overrides)(?:$)/;
  const RX_SETTINGS = /Gate summary\s*\(live\)/i;
  const RX_RAW = /Raw JSON\s*\(click to expand\)/i;
  const RX_OVR_LIVE = /Rule Overrides\s*\(live\b/i;
  const RX_LIVE_FROM_API = /live from\s*\/api/i;

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }

  function isTooBroad(box){
    // Avoid hiding wrappers that contain other important cards
    const t = (box && box.textContent) ? box.textContent : "";
    return /Endpoint Probes/i.test(t) || /Runs & Reports/i.test(t);
  }

  function findPanelFrom(el){
    // Prefer nearest "card-like" container, but don't jump to page wrapper
    let cur = el;
    for (let i=0; i<12 && cur && cur !== document.body; i++){
      if (cur.matches && cur.matches(".vsp-card,.vsp-panel,.card,.panel,section,article,div")){
        const hasPreOrDetails = !!(cur.querySelector && (cur.querySelector("pre") || cur.querySelector("details")));
        if (hasPreOrDetails && !isTooBroad(cur)) return cur;
      }
      cur = cur.parentElement;
    }
    return null;
  }

  function hideBox(box, why){
    if (!box || box.dataset.vspHideLiveJson === "1") return;
    box.dataset.vspHideLiveJson = "1";
    box.style.display = "none";
    // console.log("[VSP] hide live json:", why);
  }

  function hasBtnText(box, rx){
    if (!box || !box.querySelectorAll) return false;
    return Array.from(box.querySelectorAll("button,a")).some(x => rx.test(((x.textContent||"").trim())));
  }

  function sweep(){
    try{
      const path = location.pathname || "";
      if (!RX_PATH.test(path)) return;

      if (/\/c\/settings$/.test(path)){
        // Hide "Gate summary (live)" block (debug live JSON)
        const candidates = Array.from(document.querySelectorAll("pre,details,summary,div,section,article"));
        for (const n of candidates){
          const t = ((n.textContent||"").trim());
          if (!t) continue;
          if (!RX_SETTINGS.test(t) and not RX_RAW.test(t)):
            continue
        }
      }
    }catch(e){}
  }

  // NOTE: The python above can't embed Python-style boolean. We'll implement sweep below in JS correctly.
})();
"""
    # We will insert a corrected JS patch (no Python booleans) right after.
    patch2 = r"""
/* VSP_P130_HIDE_LIVE_JSON_PANELS_V1 (runtime) */
(function(){
  const RX_PATH = /(?:^|\/)c\/(settings|rule_overrides)(?:$)/;
  const RX_SETTINGS = /Gate summary\s*\(live\)/i;
  const RX_RAW = /Raw JSON\s*\(click to expand\)/i;
  const RX_OVR_LIVE = /Rule Overrides\s*\(live\b/i;
  const RX_LIVE_FROM_API = /live from\s*\/api/i;

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }
  function isTooBroad(box){
    const t = (box && box.textContent) ? box.textContent : "";
    return /Endpoint Probes/i.test(t) || /Runs & Reports/i.test(t);
  }
  function findPanelFrom(el){
    let cur = el;
    for (let i=0; i<12 && cur && cur !== document.body; i++){
      if (cur.matches && cur.matches(".vsp-card,.vsp-panel,.card,.panel,section,article,div")){
        const hasPreOrDetails = !!(cur.querySelector && (cur.querySelector("pre") || cur.querySelector("details")));
        if (hasPreOrDetails && !isTooBroad(cur)) return cur;
      }
      cur = cur.parentElement;
    }
    return null;
  }
  function hideBox(box){
    if (!box || box.dataset.vspHideLiveJson === "1") return;
    box.dataset.vspHideLiveJson = "1";
    box.style.display = "none";
  }
  function hasBtnText(box, rx){
    if (!box || !box.querySelectorAll) return false;
    return Array.from(box.querySelectorAll("button,a")).some(x => rx.test(((x.textContent||"").trim())));
  }

  function sweep(){
    try{
      const path = location.pathname || "";
      if (!RX_PATH.test(path)) return;

      // /c/settings: remove Gate summary (live) debug panel
      if (/\/c\/settings$/.test(path)){
        const nodes = Array.from(document.querySelectorAll("pre,details,summary,div,section,article"));
        for (const n of nodes){
          const t = ((n.textContent||"").trim());
          if (!t) continue;
          if (!(RX_SETTINGS.test(t) || RX_RAW.test(t))) continue;

          const box = findPanelFrom(n);
          if (!box) continue;
          const bt = (box.textContent||"");
          if (RX_SETTINGS.test(bt) || RX_RAW.test(bt)) hideBox(box);
        }
      }

      // /c/rule_overrides: remove the live-from-api debug panel; keep editor (LOAD/SAVE/EXPORT)
      if (/\/c\/rule_overrides$/.test(path)){
        const pres = Array.from(document.querySelectorAll("pre"));
        for (const pre of pres){
          const box = findPanelFrom(pre);
          if (!box) continue;

          const bt = (box.textContent||"");
          const looksLikeLive = RX_OVR_LIVE.test(bt) || RX_LIVE_FROM_API.test(bt);
          if (!looksLikeLive) continue;

          const hasOpen = hasBtnText(box, /\bopen\b/i);
          const hasLoad = hasBtnText(box, /^load$/i);
          const hasSave = hasBtnText(box, /^save$/i);
          const hasExport = hasBtnText(box, /^export$/i);

          // Live panel usually has Open (and maybe JSON). Editor has LOAD/SAVE/EXPORT.
          if (hasOpen && !(hasLoad || hasSave || hasExport)) hideBox(box);
        }
      }
    }catch(e){}
  }

  onReady(() => {
    sweep();
    setTimeout(sweep, 150);
    setTimeout(sweep, 600);
    setTimeout(sweep, 1500);
  });

  try{
    const mo = new MutationObserver(() => sweep());
    mo.observe(document.documentElement, {subtree:true, childList:true});
  }catch(e){}

  console.log("[VSP] installed P130 (hide live JSON panels)");
})();
"""
    # Make sure we don't accidentally duplicate old broken placeholder.
    # Remove any partial/incorrect P130 placeholder if present (defensive).
    s2 = re.sub(r"/\*\s*VSP_P130_HIDE_LIVE_JSON_PANELS_V1[\s\S]*?\*/\s*\(function\(\)\{[\s\S]*?\}\)\(\);\s*",
                "", s, flags=re.M)
    s2 = s2.rstrip() + "\n" + patch2 + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended P130 into static/js/vsp_c_common_v1.js")
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F"
  echo "[OK] JS syntax OK"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
