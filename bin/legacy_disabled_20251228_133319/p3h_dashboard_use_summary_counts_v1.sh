#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
files=(
  static/js/vsp_dashboard_comm_enhance_v1.js
  static/js/vsp_dashboard_live_v2.V1_baseline.js
)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date

echo "== [0] backup =="
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_p3h_${TS}"
  echo "[BACKUP] ${f}.bak_p3h_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

files = [
  "static/js/vsp_dashboard_comm_enhance_v1.js",
  "static/js/vsp_dashboard_live_v2.V1_baseline.js",
]

MARK="VSP_P3H_DASH_USE_SUMMARY_COUNTS_V1"

helper = r'''
// === __MARK__ helper ===
function __vspNormalizeSevKey(k){
  k = (k||"").toString().toUpperCase();
  if(k==="MEDIUMPLUS" || k==="MEDIUM_PLUS" || k==="MEDIUM+") return "MEDIUM";
  return k;
}
function __vspCountsFromSummary(summary){
  const sev = (summary && summary.severity_counts) ? summary.severity_counts : null;
  const tool = (summary && summary.tool_counts) ? summary.tool_counts : null;
  if(!sev && !tool) return null;
  const sev2 = {};
  if(sev){
    for(const [k,v] of Object.entries(sev)){
      const kk = __vspNormalizeSevKey(k);
      sev2[kk] = (sev2[kk]||0) + (Number(v)||0);
    }
  }
  return { severity: sev2, tool: tool || {} };
}
function __vspCountsFromFindings(findings){
  const sev = {}, tool = {};
  (findings||[]).forEach(it=>{
    const s = __vspNormalizeSevKey((it && it.severity) || "INFO");
    sev[s] = (sev[s]||0) + 1;
    const t = ((it && it.tool) || "UNKNOWN").toString();
    tool[t] = (tool[t]||0) + 1;
  });
  return { severity: sev, tool: tool };
}
// === END __MARK__ helper ===
'''.replace("__MARK__", MARK).strip()

def patch_one(path: str):
  p = Path(path)
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    print("[SKIP] already:", path)
    return 0

  # inject helper near top (after first line comment if present)
  if s.startswith("/*"):
    idx = s.find("*/")
    if idx != -1:
      insert_at = idx+2
      s = s[:insert_at] + "\n\n" + helper + "\n\n" + s[insert_at:]
    else:
      s = helper + "\n\n" + s
  else:
    s = helper + "\n\n" + s

  # best-effort: wherever code parses datasource json, add:
  # const __c = __vspCountsFromSummary(data.summary) || __vspCountsFromFindings(data.findings);
  # and expose __c.severity/__c.tool via window for existing render code to reuse if it wants.
  #
  # We'll patch on "data.findings" usage patterns.
  # 1) Replace "const findings = data.findings" with counts logic.
  s2, n1 = re.subn(
    r'(?m)^\s*(const|let)\s+findings\s*=\s*(data\.findings)\s*\|\|\s*\[\]\s*;\s*$',
    r'\g<0>\nconst __vspCounts = __vspCountsFromSummary(data.summary) || __vspCountsFromFindings(findings);\nwindow.__VSP_DASH_COUNTS__ = __vspCounts;',
    s
  )
  s = s2

  # 2) If pattern not found, still try a generic inject right after JSON fetch parse:
  # look for "const data = await res.json()" or "let data = await r.json()"
  if "window.__VSP_DASH_COUNTS__" not in s:
    s2, n2 = re.subn(
      r'(await\s+\w+\.json\(\)\s*;)',
      r'\1\ntry{ const __vspCounts = __vspCountsFromSummary(data.summary) || __vspCountsFromFindings(data.findings); window.__VSP_DASH_COUNTS__ = __vspCounts; }catch(e){}',
      s,
      count=1
    )
    s = s2

  # 3) Provide easy accessors for existing KPI functions:
  # Replace occurrences of "data.findings" in count computations is too risky.
  # Instead, we add a small shim: if code calls a function like buildKpis(findings),
  # it can now use window.__VSP_DASH_COUNTS__ manually. (Non-breaking.)
  p.write_text(s, encoding="utf-8")
  print("[OK] patched:", path)
  return 1

patched=0
for f in files:
  patched += patch_one(f)

print("[DONE] patched_files=", patched)
PY

echo "== [1] syntax sanity (node) =="
node -c static/js/vsp_dashboard_comm_enhance_v1.js >/dev/null
node -c static/js/vsp_dashboard_live_v2.V1_baseline.js >/dev/null
echo "[OK] node -c passed"

echo "[DONE] p3h_dashboard_use_summary_counts_v1"
