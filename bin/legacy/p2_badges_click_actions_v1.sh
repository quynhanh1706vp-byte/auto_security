#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_click_${TS}"
echo "[BACKUP] ${JS}.bak_click_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_P2_BADGES_CLICK_ACTIONS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# We patch inside the existing badges snippet by replacing mkBadge() to support click + dataset
# Find the mkBadge function inside our marker block
block_pat = re.compile(r"(// ===================== VSP_P2_BADGES_RID_OVERALL_V1 =====================.*?// ===================== /VSP_P2_BADGES_RID_OVERALL_V1 =====================)", re.S)
m = block_pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find badges block (VSP_P2_BADGES_RID_OVERALL_V1)")

block = m.group(1)

# Replace mkBadge with a richer version (only inside the block)
mk_old = re.compile(r"function\s+mkBadge\s*\(\s*cls\s*,\s*text\s*\)\s*\{\s*var\s+el\s*=\s*document\.createElement\(\"span\"\);\s*el\.className\s*=\s*\"vsp-badge\s+\"\s*\+\s*cls;\s*el\.textContent\s*=\s*text;\s*return\s+el;\s*\}", re.S)
if not mk_old.search(block):
    raise SystemExit("[ERR] mkBadge() pattern not found inside badges block")

mk_new = r'''
    function mkBadge(cls, text, opts){
      opts = opts || {};
      var el = document.createElement("span");
      el.className = "vsp-badge " + cls + (opts.click ? " vsp-badge-click" : "");
      el.textContent = text;
      if (opts.click){
        el.style.cursor = "pointer";
        el.title = opts.title || "Open";
        if (opts.action) el.dataset.vspAction = opts.action;
        if (opts.payload) el.dataset.vspPayload = opts.payload;
        el.addEventListener("click", function(){
          try{
            var a = el.dataset.vspAction || "";
            var p = el.dataset.vspPayload || "";
            if (a === "runs_rid"){
              // p is rid
              location.href = "/runs?rid=" + encodeURIComponent(p);
            } else if (a === "dash_gate"){
              location.href = "/vsp5?gate=1";
            }
          }catch(e){}
        });
      }
      return el;
    }
'''

block2 = mk_old.sub(mk_new, block, count=1)

# Add CSS for hover feedback (inside ensureStyle text)
block2 = block2.replace(
  ".vsp-badge.gray{opacity:.85}",
  ".vsp-badge.gray{opacity:.85}\n        .vsp-badge-click:hover{filter:brightness(1.18)}"
)

# Now patch the render part: create clickable badges
# Replace the final rendering lines with clickable variants
block2 = re.sub(
  r'c\.appendChild\(mkBadge\("gray",\s*"RID:\s*"\s*\+\s*\(rid\s*\?\s*shortRid\(rid\)\s*:\s*"n/a"\)\)\);\s*var\s+oc\s*=\s*pickOverallClass\(overall\);\s*c\.appendChild\(mkBadge\(oc,\s*"Overall:\s*"\s*\+\s*\(overall\s*\?\s*overall\.toString\(\)\.toUpperCase\(\)\s*:\s*"n/a"\)\)\);\s*if\s*\(degraded\)\{\s*c\.appendChild\(mkBadge\("amber",\s*"DEGRADED"\)\);\s*\}',
  'c.appendChild(mkBadge("gray", "RID: " + (rid ? shortRid(rid) : "n/a"), {click:true, action:"runs_rid", payload: rid || "", title:"Open Runs & Reports (RID)"}));\n        var oc = pickOverallClass(overall);\n        c.appendChild(mkBadge(oc, "Overall: " + (overall ? overall.toString().toUpperCase() : "n/a"), {click:true, action:"dash_gate", payload:"1", title:"Open Dashboard (Gate)"}));\n        if (degraded){\n          c.appendChild(mkBadge("amber", "DEGRADED", {click:true, action:"dash_gate", payload:"1", title:"Open Dashboard (Gate)"}));\n        }',
  block2,
  flags=re.S
)

# Write back
s2 = s[:m.start(1)] + block2 + s[m.end(1):]
p.write_text(s2, encoding="utf-8")
print("[OK] patched clickable badges")

# Append a marker at end (simple)
p.write_text(p.read_text(encoding="utf-8", errors="ignore") + "\n/* "+MARK+" */\n", encoding="utf-8")
print("[OK] marker appended:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check $JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] P2.4 click actions applied. Reload /vsp5 then click RID/Overall badges."
