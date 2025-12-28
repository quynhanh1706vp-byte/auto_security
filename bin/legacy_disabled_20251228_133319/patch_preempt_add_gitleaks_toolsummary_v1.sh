#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_preempt_add_gitleaks_toolsummary_${TS}"
echo "[BACKUP] $APP.bak_preempt_add_gitleaks_toolsummary_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_PREEMPT_ADD_GITLEAKS_TOOLSUMMARY_V1 ==="

# 0) remove any previously injected raw-json gitleaks blocks (both tags we used)
t = re.sub(r"(?s)\n?\s*#\s*===\s*VSP_WSGI_PREEMPT_ADD_GITLEAKS_V1\s*===.*?^\s*pass\s*\n", "\n", t, flags=re.M)
t = re.sub(r"(?s)\n?\s*#\s*===\s*VSP_STATUS_V2_ADD_GITLEAKS_FIELDS_ANCHOR_V3\s*===.*?^\s*pass\s*\n", "\n", t, flags=re.M)

if TAG in t:
    print("[OK] tag exists, skip")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# 1) find semgrep+trivy injection lines using _vsp_inject_tool_summary
# support both ci var: ci_dir or _ci
pat = re.compile(
    r"(?m)^(?P<ind>\s*)resp\s*=\s*_vsp_inject_tool_summary\(\s*resp\s*,\s*(?P<civar>\w+)\s*,\s*['\"]semgrep['\"]\s*,\s*['\"]semgrep_summary\.json['\"]\s*\)\s*$"
    r"(?:\r?\n)"
    r"^(?P=ind)resp\s*=\s*_vsp_inject_tool_summary\(\s*resp\s*,\s*(?P=civar)\s*,\s*['\"]trivy['\"]\s*,\s*['\"]trivy_summary\.json['\"]\s*\)\s*$"
)

m = pat.search(t)
if not m:
    # fallback: just find the trivy line and insert after it (still safe)
    pat2 = re.compile(
        r"(?m)^(?P<ind>\s*)resp\s*=\s*_vsp_inject_tool_summary\(\s*resp\s*,\s*(?P<civar>\w+)\s*,\s*['\"]trivy['\"]\s*,\s*['\"]trivy_summary\.json['\"]\s*\)\s*$"
    )
    m2 = pat2.search(t)
    if not m2:
        raise SystemExit("[ERR] cannot find preempt tool summary injection lines for semgrep/trivy")
    ind = m2.group("ind")
    civar = m2.group("civar")
    insert_pos = m2.end()
else:
    ind = m.group("ind")
    civar = m.group("civar")
    insert_pos = m.end()

ins = "\n" + f"{ind}{TAG}\n" + f"{ind}resp = _vsp_inject_tool_summary(resp, {civar}, \"gitleaks\", \"gitleaks_summary.json\")\n"
t2 = t[:insert_pos] + ins + t[insert_pos:]

p.write_text(t2, encoding="utf-8")
print("[OK] inserted gitleaks _vsp_inject_tool_summary after trivy with civar=", civar, "indent=", repr(ind))
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
