#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

# pick latest backup created by v2
BAK="$(ls -1t "${APP}.bak_gitleaks_statusv2_v2_"* 2>/dev/null | head -n 1 || true)"
if [ -z "${BAK}" ]; then
  echo "[ERR] cannot find backup like: ${APP}.bak_gitleaks_statusv2_v2_*"
  exit 1
fi

echo "[RESTORE] ${BAK} -> ${APP}"
cp -f "${BAK}" "${APP}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_V1"

# remove any old broken insert (if exists)
t = re.sub(r"(?s)\n?\s*#\s*===\s*VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_V1\s*===.*?^\s*pass\s*\n", "\n", t, flags=re.M)

# find a good anchor line inside the final-status builder scope
anchor_re_list = [
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]trivy_counts['\"]\]\s*="),
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]semgrep_counts['\"]\]\s*="),
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]kics_counts['\"]\]\s*="),
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]has_trivy['\"]\]\s*="),
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]has_semgrep['\"]\]\s*="),
    re.compile(r"(?m)^(?P<ind>\s*)status\[['\"]has_kics['\"]\]\s*="),
]

m = None
for r in anchor_re_list:
    m = r.search(t)
    if m:
        break

if not m:
    raise SystemExit("[ERR] cannot find anchor line like status['trivy_counts']/semgrep/kics in vsp_demo_app.py")

ind = m.group("ind")
# insert AFTER the anchor line
line_end = t.find("\n", m.end())
if line_end == -1:
    line_end = m.end()

inject_lines = [
f"{ind}# === {TAG} ===",
f"{ind}try:",
f"{ind}  _gl_paths = [",
f"{ind}    os.path.join(ci_run_dir,'gitleaks','gitleaks_summary.json'),",
f"{ind}    os.path.join(ci_run_dir,'gitleaks_summary.json'),",
f"{ind}  ]",
f"{ind}  gitleaks_summary = None",
f"{ind}  for _p in _gl_paths:",
f"{ind}    if os.path.exists(_p):",
f"{ind}      gitleaks_summary = _safe_load_json(_p)",
f"{ind}      break",
f"{ind}  if isinstance(gitleaks_summary, dict):",
f"{ind}    status['gitleaks_verdict'] = gitleaks_summary.get('verdict')",
f"{ind}    status['gitleaks_total']   = gitleaks_summary.get('total')",
f"{ind}    status['gitleaks_counts']  = gitleaks_summary.get('counts')",
f"{ind}    status['has_gitleaks']     = True",
f"{ind}except Exception:",
f"{ind}  pass",
]

inject = "\n" + "\n".join(inject_lines) + "\n"

t2 = t[:line_end+1] + inject + t[line_end+1:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted gitleaks injector with indent =", repr(ind))
PY

python3 -m py_compile "${APP}"
echo "[OK] py_compile OK"

echo "DONE"
