#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_STABILIZE_KPI_V2_LABELS"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_stabkpi2_${TS}"
echo "[BACKUP] ${JS}.bak_stabkpi2_${TS}"

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

# Find our stabilize block and patch two functions inside it:
# - findLabelNodes(): currently exact match === label
# - applyOnce(): currently tries Medium and Medium* (exact) -> fails if UI text has star/space
blk_start = "/* ===================== VSP_P3_STABILIZE_KPI_V1 ===================== */"
blk_end   = "/* ===================== /VSP_P3_STABILIZE_KPI_V1 ===================== */"
a = s.find(blk_start)
b = s.find(blk_end)
if a < 0 or b < 0 or b <= a:
    raise SystemExit("[ERR] cannot locate STABILIZE_KPI_V1 block")

block = s[a:b]

# 1) replace findLabelNodes exact match with tolerant match (startsWith / includes)
block2 = re.sub(
    r'function\s+findLabelNodes\s*\(\s*label\s*\)\s*\{.*?\n\s*\}',
    r'''function findLabelNodes(label){
      label = normText(label);
      const els = Array.from(document.querySelectorAll("div,span,p,h1,h2,h3,h4,td,th"));
      return els.filter(el => {
        const t = normText(el.textContent);
        if(!t) return false;
        if(t === label) return true;
        // tolerant: Medium* / Medium (Risk...) / Total findings (extra notes)
        if(t.startsWith(label)) return true;
        if(label.length >= 4 && t.includes(label)) return true;
        // special: label "Medium*" should match anything starting with "Medium"
        if(label.replace("*","") && t.startsWith(label.replace("*",""))) return true;
        return false;
      });
    }''',
    block,
    flags=re.S
)

# 2) force applyOnce to use tolerant labels: Medium* (or Medium) and Total findings
# We only tweak label strings (no structural change)
block2 = block2.replace(
    'setKpiByLabel("Medium", medium) || setKpiByLabel("Medium*", medium);',
    'setKpiByLabel("Medium*", medium) || setKpiByLabel("Medium", medium);'
)

# 3) add a tiny debug log to confirm it runs
if "STABILIZE_KPI_V2_LABELS" not in block2:
    block2 = block2.replace(
        'try{ console.log("[STABILIZE_KPI_V1] applied", {rid, total, critical, high, medium}); }catch(_){}',
        'try{ console.log("[STABILIZE_KPI_V2_LABELS] applied", {rid, total, critical, high, medium}); }catch(_){}'
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

echo "[DONE] stabilize labels V2 installed. HARD refresh: $BASE/vsp5?rid=VSP_CI_20251215_173713"
