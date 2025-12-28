#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_hide_legacy_v2_${TS}"
echo "[BACKUP] ${JS}.bak_hide_legacy_v2_${TS}"

python3 - "$JS" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_GATE_STORY_HIDE_LEGACY_STRIP_WHEN_V7C_V2"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=r"""
/* VSP_P1_GATE_STORY_HIDE_LEGACY_STRIP_WHEN_V7C_V2 */
(()=> {
  if (window.__vsp_p1_hide_legacy_strip_v2) return;
  window.__vsp_p1_hide_legacy_strip_v2 = true;

  const TOOLS = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];

  function toolHits(txt){
    txt = (txt||"");
    let h=0;
    for (const t of TOOLS) if (txt.includes(t)) h++;
    return h;
  }

  function isLegacyBadgeRow(el, v7c){
    if (!el || !el.textContent) return false;
    if (el === v7c) return false;
    if (v7c && (v7c.contains(el) || el.contains(v7c))) return false;

    const tx = (el.textContent||"").trim();
    if (!tx) return false;
    if (tx.includes("Tool truth")) return false; // đừng đụng V7C
    // row badge thường chứa nhiều tool names
    return toolHits(tx) >= 4;
  }

  function hideLegacy(){
    const v7c = document.getElementById("vsp_tool_truth_strip_v7c");
    if (!v7c) return;

    // 1) hide label "Tool strip..."
    for (const el of Array.from(document.querySelectorAll("div,span,p,strong,small"))){
      const tx = (el.textContent||"").trim();
      if (/^Tool\s*strip\b/i.test(tx)){
        el.style.display="none";
        if (el.parentElement) el.parentElement.style.display="none";
      }
    }

    // 2) hide legacy badge row(s) that appear BEFORE v7c in DOM order
    const candidates = Array.from(document.querySelectorAll("div,section,article,span"));
    let hidden=0;
    for (const el of candidates){
      if (!isLegacyBadgeRow(el, v7c)) continue;

      // el is before v7c?
      const rel = el.compareDocumentPosition(v7c);
      const elIsBefore = (rel & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;

      if (elIsBefore){
        el.style.display="none";
        hidden++;
      }
    }

    if (!window.__vsp_p1_hide_legacy_strip_v2_logged){
      window.__vsp_p1_hide_legacy_strip_v2_logged = true;
      console.log("[GateStoryV1] hide legacy strip V2: hidden=", hidden);
    }
  }

  setTimeout(hideLegacy, 150);
  setTimeout(hideLegacy, 600);
  setInterval(hideLegacy, 2000);
})();
"""
p.write_text(s + "\n\n" + addon + "\n/* "+marker+" */\n", encoding="utf-8")
print("[OK] appended", marker)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK"
fi

sudo systemctl restart vsp-ui-8910.service >/dev/null 2>&1 || true
echo "[DONE] Open /vsp5 and HARD refresh (Ctrl+Shift+R). Expect: legacy strip hidden, only Tool truth (V7C) remains."
