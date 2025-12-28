#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_gitleaks_anchor_v3_${TS}"
echo "[BACKUP] $APP.bak_fix_gitleaks_anchor_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_ANCHOR_V3 ==="
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# Candidates we expect to exist in your working preempt/final status builder
anchor_patterns = [
    r"status\[['\"]trivy_verdict['\"]\]\s*=",
    r"status\[['\"]trivy_total['\"]\]\s*=",
    r"status\[['\"]trivy_counts['\"]\]\s*=",
    r"status\[['\"]semgrep_verdict['\"]\]\s*=",
    r"status\[['\"]semgrep_total['\"]\]\s*=",
    r"status\[['\"]semgrep_counts['\"]\]\s*=",
    r"status\[['\"]kics_verdict['\"]\]\s*=",
    r"status\[['\"]kics_total['\"]\]\s*=",
    r"status\[['\"]kics_counts['\"]\]\s*=",
    # fallback: any mention of summary files
    r"trivy_summary\.json",
    r"semgrep_summary\.json",
    r"kics_summary\.json",
]

m = None
for pat in anchor_patterns:
    m = re.search(r"(?m)^(?P<ind>\s*).*" + pat + r".*$", t)
    if m:
        break

if not m:
    raise SystemExit("[ERR] cannot find any known anchor (kics/semgrep/trivy) in vsp_demo_app.py")

ind = m.group("ind")
# insert AFTER this anchor line
line_end = t.find("\n", m.end())
if line_end == -1:
    line_end = m.end()

inject = "\n".join([
    f"{ind}{TAG}",
    f"{ind}try:",
    f"{ind}  import os, json",
    f"{ind}  _gl_paths = [",
    f"{ind}    os.path.join(ci_run_dir,'gitleaks','gitleaks_summary.json'),",
    f"{ind}    os.path.join(ci_run_dir,'gitleaks_summary.json'),",
    f"{ind}  ]",
    f"{ind}  _gl = None",
    f"{ind}  for _p in _gl_paths:",
    f"{ind}    if os.path.exists(_p):",
    f"{ind}      with open(_p, 'r', encoding='utf-8', errors='ignore') as _f:",
    f"{ind}        _gl = json.load(_f)",
    f"{ind}      break",
    f"{ind}  if isinstance(_gl, dict):",
    f"{ind}    status['gitleaks_verdict'] = _gl.get('verdict')",
    f"{ind}    status['gitleaks_total']   = _gl.get('total')",
    f"{ind}    status['gitleaks_counts']  = _gl.get('counts')",
    f"{ind}    status['has_gitleaks']     = True",
    f"{ind}except Exception:",
    f"{ind}  pass",
    "",
])

t2 = t[:line_end+1] + "\n" + inject + t[line_end+1:]
p.write_text(t2, encoding="utf-8")
print("[OK] injected gitleaks after anchor with indent =", repr(ind))
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"
echo "DONE"
