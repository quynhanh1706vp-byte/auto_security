#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_preempt_gitleaks_overall_v2_${TS}"
echo "[BACKUP] $APP.bak_preempt_gitleaks_overall_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_PREEMPT_GITLEAKS_AND_OVERALL_V2 ==="
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# Clean older gitleaks injection tags if any
t = re.sub(r"(?s)\n?\s*#\s*===\s*VSP_WSGI_PREEMPT_ADD_GITLEAKS_V1\s*===.*?^\s*pass\s*\n", "\n", t, flags=re.M)
t = re.sub(r"(?s)\n?\s*#\s*===\s*VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_ANCHOR_V3\s*===.*?^\s*pass\s*\n", "\n", t, flags=re.M)

# Find ALL lines injecting trivy summary via helper and insert after them
pat = re.compile(
    r"(?m)^(?P<ind>\s*)resp\s*=\s*_vsp_inject_tool_summary\(\s*resp\s*,\s*(?P<civar>\w+)\s*,\s*['\"]trivy['\"]\s*,\s*['\"]trivy_summary\.json['\"]\s*\)\s*$"
)

matches = list(pat.finditer(t))
if not matches:
    raise SystemExit("[ERR] cannot find any trivy _vsp_inject_tool_summary(resp, <ci>, 'trivy', 'trivy_summary.json') line")

inject_blocks = []
for m in matches:
    ind = m.group("ind")
    civar = m.group("civar")
    inject = "\n".join([
        f"{ind}{TAG}",
        f"{ind}# defaults for commercial contract (avoid nulls)",
        f"{ind}resp.setdefault('overall_verdict','')",
        f"{ind}resp.setdefault('has_gitleaks', False)",
        f"{ind}resp.setdefault('gitleaks_verdict','')",
        f"{ind}resp.setdefault('gitleaks_total', 0)",
        f"{ind}resp.setdefault('gitleaks_counts', {{}})",
        f"{ind}# inject gitleaks summary like semgrep/trivy",
        f"{ind}resp = _vsp_inject_tool_summary(resp, {civar}, 'gitleaks', 'gitleaks_summary.json')",
        f"{ind}# pick overall from run_gate_summary.json if exists",
        f"{ind}try:",
        f"{ind}    from pathlib import Path as _P",
        f"{ind}    _g = _vsp__read_json_if_exists_v2(_P({civar}) / 'run_gate_summary.json')",
        f"{ind}    if isinstance(_g, dict):",
        f"{ind}        resp['overall_verdict'] = str(_g.get('overall') or resp.get('overall_verdict') or '')",
        f"{ind}except Exception:",
        f"{ind}    pass",
        ""
    ])
    inject_blocks.append((m.end(), "\n"+inject))

# Apply inserts from bottom to top to keep offsets valid
out = t
for pos, blk in sorted(inject_blocks, key=lambda x: x[0], reverse=True):
    out = out[:pos] + blk + out[pos:]

p.write_text(out, encoding="utf-8")
print(f"[OK] inserted gitleaks+overall block after {len(matches)} trivy-inject sites")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
