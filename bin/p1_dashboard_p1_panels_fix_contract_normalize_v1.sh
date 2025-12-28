#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_contract_${TS}"
echo "[BACKUP] ${JS}.bak_fix_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

start = s.find("VSP_P1_DASHBOARD_P1_PANELS_V1")
if start < 0:
    raise SystemExit("[ERR] P1 panels marker not found")

sub = s[start:]

# Insert normalize helper right after fetchJSON() (first occurrence inside addon)
ins_pt = re.search(r'\n\s*async\s+function\s+fetchJSON\s*\(\s*url\s*\)\s*\{', sub)
if not ins_pt:
    raise SystemExit("[ERR] cannot locate fetchJSON() in addon")

# Find end of fetchJSON block (we replaced it earlier; just find the next '}\n' after 'async function fetchJSON')
m_end = re.search(r'\n\s*async\s+function\s+fetchJSON\s*\(\s*url\s*\)\s*\{.*?\n\s*\}\n', sub, flags=re.S)
if not m_end:
    raise SystemExit("[ERR] cannot locate fetchJSON() block end in addon")

helper = r'''
  function __vspP1_normFindingsPayload(x){
    // Accept multiple shapes from run_file_allow:
    // - {meta:{counts_by_severity}, findings:[...]}
    // - {meta:{...}, items:[...]}
    // - {meta:{...}, findings:{items:[...]}} (nested)
    // - {counts_by_severity:{...}, findings:[...]} (rare)
    let o = x;
    if (!o || typeof o !== "object") return o;

    // If findings missing but items present
    if (!("findings" in o) && Array.isArray(o.items)) {
      o.findings = o.items;
    }

    // If findings is nested container with items
    if (o.findings && typeof o.findings === "object" && !Array.isArray(o.findings) && Array.isArray(o.findings.items)) {
      o.findings = o.findings.items;
    }

    // Ensure meta exists
    if (!o.meta || typeof o.meta !== "object") o.meta = {};

    // Accept counts_by_severity from top-level if meta missing
    if (!o.meta.counts_by_severity && o.counts_by_severity && typeof o.counts_by_severity === "object") {
      o.meta.counts_by_severity = o.counts_by_severity;
    }

    return o;
  }
'''

sub2 = sub[:m_end.end()] + "\n" + helper + "\n" + sub[m_end.end():]
s2 = s[:start] + sub2

# Now replace strict contract check block
pat = re.compile(
    r'const\s+meta\s*=\s*\(findings\s*&&\s*findings\.meta\)\s*\|\|\s*\{\}\s*;'
    r'\s*const\s+cbs\s*=\s*meta\.counts_by_severity\s*;'
    r'\s*if\s*\(\s*!cbs\s*\|\|\s*typeof\s+cbs\s*!==\s*"object"\s*\|\|\s*!Array\.isArray\(\s*findings\.findings\s*\)\s*\)\s*\{'
    r'.*?return;\s*\}',
    re.S
)

m = pat.search(s2, pos=start)
if not m:
    raise SystemExit("[ERR] cannot find old strict contract block to replace (pattern mismatch).")

new_check = r'''
    findings = __vspP1_normFindingsPayload(findings);

    const meta = (findings && findings.meta) || {};
    const cbs = meta.counts_by_severity;

    // Debug (1 line) to avoid blind mismatch
    try{
      console.log("[VSP][DashP1PanelsV1][DBG] findings_keys=", Object.keys(findings||{}),
                  "meta_keys=", Object.keys(meta||{}),
                  "has_cbs=", !!cbs,
                  "findings_is_array=", Array.isArray(findings && findings.findings),
                  "type_findings=", typeof (findings && findings.findings));
    }catch(e){}

    if (!cbs || typeof cbs!=="object" || !Array.isArray(findings.findings)){
      mount.innerHTML="";
      mount.appendChild(el("div",{class:"vspP1Err"},[
        "Data contract mismatch (normalized): need meta.counts_by_severity + findings[]"
      ]));
      return;
    }
'''

s3 = s2[:m.start()] + new_check + s2[m.end():]
p.write_text(s3, encoding="utf-8")
print("[OK] contract normalize + debug applied")
PY

echo "[DONE] contract normalize applied."
echo "Next: restart UI then HARD refresh /vsp5."
