#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_dash_contract_${TS}"
echo "[BACKUP] ${JS}.bak_dash_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASH_CONTRACT_ENFORCE_V1"
if MARK not in s:
    inject = r"""
/* VSP_P1_DASH_CONTRACT_ENFORCE_V1
 * Dashboard contract: ONLY
 *  - /api/vsp/rid_latest_gate_root
 *  - /api/vsp/run_file_allow?rid=<RID>&path=run_gate_summary.json
 * Disable legacy latest_rid + noisy id-check logs.
 */
try { window.__vsp_dash_contract_only_summary_v1 = true; } catch(_){}
try { window.__vsp_latest_rid_url_v1 = "/api/vsp/rid_latest_gate_root"; } catch(_){}
"""
    # inject near top
    m = re.search(r"/\*[\s\S]{0,2500}?\*/", s)
    if m:
        s = s[:m.end()] + "\n" + inject + s[m.end():]
    else:
        s = inject + "\n" + s

# 1) Replace legacy endpoint everywhere (string literal + template)
s = s.replace("/api/vsp/latest_rid", "/api/vsp/rid_latest_gate_root")
s = s.replace("/api/vsp/rid_latest", "/api/vsp/rid_latest_gate_root")

# 2) If there is any variable holding latest rid url, canonicalize it
# (covers patterns like const LATEST_RID="/api/vsp/latest_rid";)
s = re.sub(r'(["\'])/api/vsp/latest_rid\1', r'"/api/vsp/rid_latest_gate_root"', s)
s = re.sub(r'(["\'])/api/vsp/rid_latest\1', r'"/api/vsp/rid_latest_gate_root"', s)

# 3) Disable noisy id-check logs (keep other logs)
# Turn console.log("[VSP][DASH][V6F] ...") into no-op.
s = re.sub(r'console\.log\(\s*([`"\'])\[VSP\]\[DASH\]\[V6F\][\s\S]*?\)\s*;?',
           '/* [VSP][DASH][V6F] suppressed by VSP_P1_DASH_CONTRACT_ENFORCE_V1 */',
           s)

# 4) Force “latest rid” getter to prefer rid_latest_gate_root response if code does fallbacks.
# This is conservative: it only touches blocks that contain 'rid_latest_gate_root' nearby.
def force_rid_picker(block: str) -> str:
    # ensure when parsing JSON we pick rid field first
    # common patterns: j.rid || j.run_id || ...
    block2 = re.sub(r'(j\.(?:run_id|id)\s*\|\|\s*j\.rid)',
                    'j.rid || j.run_id', block)
    return block2

# Apply only inside small windows around rid_latest_gate_root usage
for m in list(re.finditer(r'rid_latest_gate_root', s)):
    a = max(0, m.start()-1200)
    b = min(len(s), m.end()+1800)
    chunk = s[a:b]
    chunk2 = force_rid_picker(chunk)
    if chunk2 != chunk:
        s = s[:a] + chunk2 + s[b:]

# 5) Update “data contract” hint text if present (cosmetic but reduces confusion)
s = s.replace("findings.meta.counts_by_severity + findings[] required",
              "gate summary required: run_gate_summary.json (counts_total/by_tool/overall)")
s = s.replace("gate summary object required (overall/by_tool recommended)",
              "gate summary object required (overall/by_tool REQUIRED)")

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
else
  echo "[WARN] node not found, skipped syntax check"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Then verify Network: rid_latest_gate_root + run_gate_summary only."
