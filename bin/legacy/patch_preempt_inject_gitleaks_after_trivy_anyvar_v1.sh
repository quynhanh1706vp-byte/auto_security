#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_inject_gitleaks_after_trivy_anyvar_${TS}"
echo "[BACKUP] $APP.bak_inject_gitleaks_after_trivy_anyvar_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_PREEMPT_INJECT_GITLEAKS_AFTER_TRIVY_ANYVAR_V1 ==="
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# Match ANY variable name on LHS, ANY ci var name, tool=trivy, file=trivy_summary.json
pat = re.compile(
    r"(?m)^(?P<ind>\s*)(?P<var>[A-Za-z_]\w*)\s*=\s*_vsp_inject_tool_summary"
    r"\(\s*(?P=var)\s*,\s*(?P<civar>[A-Za-z_]\w*)\s*,\s*['\"]trivy['\"]\s*,\s*['\"]trivy_summary\.json['\"]\s*\)\s*$"
)

ms = list(pat.finditer(t))
if not ms:
    raise SystemExit("[ERR] cannot find any line like: X = _vsp_inject_tool_summary(X, CI, 'trivy', 'trivy_summary.json')")

# Insert after each match (from bottom to top to keep positions stable)
out = t
for m in reversed(ms):
    ind = m.group("ind")
    var = m.group("var")
    civar = m.group("civar")
    ins = "\n".join([
        f"{ind}{TAG}",
        f"{ind}try:",
        f"{ind}    if isinstance({var}, dict):",
        f"{ind}        # avoid nulls in contract",
        f"{ind}        if {var}.get('overall_verdict', None) is None:",
        f"{ind}            {var}['overall_verdict'] = ''",
        f"{ind}        {var}.setdefault('has_gitleaks', False)",
        f"{ind}        {var}.setdefault('gitleaks_verdict', '')",
        f"{ind}        {var}.setdefault('gitleaks_total', 0)",
        f"{ind}        {var}.setdefault('gitleaks_counts', {{}})",
        f"{ind}except Exception:",
        f"{ind}    pass",
        f"{ind}{var} = _vsp_inject_tool_summary({var}, {civar}, 'gitleaks', 'gitleaks_summary.json')",
        ""
    ])
    out = out[:m.end()] + "\n" + ins + out[m.end():]

p.write_text(out, encoding="utf-8")
print(f"[OK] inserted gitleaks injector after {len(ms)} trivy-inject sites")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
