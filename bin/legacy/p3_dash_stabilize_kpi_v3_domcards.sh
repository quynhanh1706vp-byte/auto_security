#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_STABILIZE_KPI_V3_DOMCARDS"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_stabkpi3_${TS}"
echo "[BACKUP] ${JS}.bak_stabkpi3_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, re

js_path=sys.argv[1]
mark=sys.argv[2]
p=Path(js_path)
s=p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

# Locate stabilize V1 block and inject a DOM-card-based setter inside it (override older setter)
blk_start = "/* ===================== VSP_P3_STABILIZE_KPI_V1 ===================== */"
blk_end   = "/* ===================== /VSP_P3_STABILIZE_KPI_V1 ===================== */"
a = s.find(blk_start)
b = s.find(blk_end)
if a < 0 or b < 0 or b <= a:
    raise SystemExit("[ERR] cannot locate STABILIZE_KPI_V1 block")

block = s[a:b]

# Inject helper right before applyOnce() definition (first occurrence)
ins_pt = block.find("async function applyOnce()")
if ins_pt < 0:
    raise SystemExit("[ERR] cannot locate applyOnce() in stabilize block")

inject = r"""
    // --- VSP_P3_STABILIZE_KPI_V3_DOMCARDS ---
    function findKpiLabelNodeExact(label){
      label = normText(label);
      const els = Array.from(document.querySelectorAll(".vsp-kpi-label,div,span,p"));
      for (const el of els){
        const t = normText(el.textContent);
        if (!t) continue;
        if (t === label) return el;
      }
      return null;
    }

    function pickLargestNumberNodeWithin(root){
      if(!root) return null;
      const cand = Array.from(root.querySelectorAll("div,span,p,h1,h2,h3,h4"))
        .filter(el => /^[0-9][0-9,]*$/.test((el.textContent||"").trim()));
      if (!cand.length) return null;
      let best=cand[0], bestSize=0;
      for (const el of cand){
        const fs = parseFloat(getComputedStyle(el).fontSize || "0") || 0;
        if (fs > bestSize){ bestSize=fs; best=el; }
      }
      return best;
    }

    function setKpiCardValue(label, value){
      // Prefer the explicit label class used by luxe cards
      let lab = findKpiLabelNodeExact(label);
      if(!lab) return false;

      // Find nearest card container: climb a bit until we contain both label and a number
      let card = lab.closest("div");
      for (let i=0;i<8 && card && card.parentElement;i++){
        const num = pickLargestNumberNodeWithin(card);
        if (num){ num.textContent = String(value); return true; }
        card = card.parentElement;
      }
      // fallback: within parent
      const num2 = pickLargestNumberNodeWithin(lab.parentElement);
      if (num2){ num2.textContent = String(value); return true; }
      return false;
    }
    // --- /VSP_P3_STABILIZE_KPI_V3_DOMCARDS ---
"""

block2 = block[:ins_pt] + inject + "\n" + block[ins_pt:]

# Replace old setKpiByLabel calls inside applyOnce() with setKpiCardValue, including Medium+
block2 = block2.replace(
    'setKpiByLabel("Total findings", total) || setKpiByLabel("Total Findings", total);',
    'setKpiCardValue("Total findings", total) || setKpiCardValue("Total Findings", total);'
)
block2 = block2.replace(
    'setKpiByLabel("High", high);',
    'setKpiCardValue("High", high);'
)
block2 = block2.replace(
    'setKpiByLabel("Medium*", medium) || setKpiByLabel("Medium", medium);',
    'setKpiCardValue("Medium+", medium) || setKpiCardValue("Medium", medium);'
)
block2 = block2.replace(
    'setKpiByLabel("Critical", critical);',
    'setKpiCardValue("Critical", critical);'
)

# Also update any remaining Medium/Medium* line if present
block2 = block2.replace(
    'setKpiByLabel("Medium+", medium) || setKpiByLabel("Medium", medium);',
    'setKpiCardValue("Medium+", medium) || setKpiCardValue("Medium", medium);'
)

# Update log tag so you can see it ran
block2 = block2.replace(
    "[STABILIZE_KPI_V2_LABELS] applied",
    "[STABILIZE_KPI_V3_DOMCARDS] applied"
)
block2 = block2.replace(
    "[STABILIZE_KPI_V1] applied",
    "[STABILIZE_KPI_V3_DOMCARDS] applied"
)

s = s[:a] + block2 + s[b:]
s += "\n/* " + mark + " */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker present =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing"; exit 2; }

echo "[DONE] stabilize KPI V3 installed. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
