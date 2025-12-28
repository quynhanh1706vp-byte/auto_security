#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_hide_legacy_${TS}"
echo "[BACKUP] ${JS}.bak_hide_legacy_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_HIDE_LEGACY_STRIP_WHEN_V7C_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r"""
/* VSP_P1_GATE_STORY_HIDE_LEGACY_STRIP_WHEN_V7C_V1 */
(()=> {
  if (window.__vsp_p1_hide_legacy_strip_v1) return;
  window.__vsp_p1_hide_legacy_strip_v1 = true;

  function tick(){
    const v7c = document.getElementById("vsp_tool_truth_strip_v7c");
    if (!v7c) return;

    // Heuristic: legacy tool strip line often contains "Tool strip" text
    const nodes = Array.from(document.querySelectorAll("div,span,p"));
    for (const el of nodes){
      const tx = (el.textContent||"").trim();
      if (/^Tool strip\s*\(/i.test(tx)){
        el.style.display = "none";
        const parent = el.parentElement;
        if (parent && parent.children && parent.children.length <= 3){
          // hide the whole legacy block if it's just label+badges
          parent.style.display = "none";
        }
      }
    }
  }
  setTimeout(tick, 200);
  setInterval(tick, 1500);
  console.log("[GateStoryV1] hide legacy tool strip when V7C present");
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Hard refresh /vsp5. Expect: only Tool truth (V7C) strip remains."
