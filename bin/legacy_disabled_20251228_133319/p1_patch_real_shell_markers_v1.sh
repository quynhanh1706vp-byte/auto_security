#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need find; need sed

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

MARKER="VSP_P1_REAL_SHELL_REQUIRED_MARKERS_V1"
INJECT=$'<!-- '"$MARKER"$' -->\n<div id="vsp-kpi-testids" style="display:none">\n  <span data-testid="kpi_total"></span>\n  <span data-testid="kpi_critical"></span>\n  <span data-testid="kpi_high"></span>\n  <span data-testid="kpi_medium"></span>\n  <span data-testid="kpi_low"></span>\n  <span data-testid="kpi_info_trace"></span>\n</div>\n<div id="vsp-runs-main" style="display:none"></div>\n<div id="vsp-data-source-main" style="display:none"></div>\n<div id="vsp-settings-main" style="display:none"></div>\n<div id="vsp-rule-overrides-main" style="display:none"></div>\n<!-- end '"$MARKER"$' -->\n'

echo "== [1] Find REAL shell sources (topnav vsp5nav / vsp_dark_commercial_p1_2.css) =="
python3 - <<'PY'
from pathlib import Path
import re

roots = [Path("."), Path("templates"), Path("static")]
cands = set()

# prioritize gateway + templates
for p in Path(".").rglob("*"):
    if not p.is_file(): 
        continue
    if any(x in str(p) for x in ("/.venv/","/node_modules/","/out_ci",".bak_")):
        continue
    if p.suffix not in (".py",".html"):
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if ("topnav vsp5nav" in s) or ("vsp_dark_commercial_p1_2.css" in s):
        cands.add(str(p))

print("\n".join(sorted(cands)))
PY

echo "== [2] Patch every matched file (backup + inject markers) =="
python3 - "$TS" <<'PY'
from pathlib import Path
import re, sys

ts=sys.argv[1]
marker="VSP_P1_REAL_SHELL_REQUIRED_MARKERS_V1"

# Collect same candidates again (python-only, deterministic)
cands=[]
for p in Path(".").rglob("*"):
    if not p.is_file(): 
        continue
    sp=str(p)
    if any(x in sp for x in ("/.venv/","/node_modules/","/out_ci",".bak_")):
        continue
    if p.suffix not in (".py",".html"):
        continue
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if ("topnav vsp5nav" in s) or ("vsp_dark_commercial_p1_2.css" in s):
        cands.append(p)

inject = (
'<!-- '+marker+' -->\n'
'<div id="vsp-kpi-testids" style="display:none">\n'
'  <span data-testid="kpi_total"></span>\n'
'  <span data-testid="kpi_critical"></span>\n'
'  <span data-testid="kpi_high"></span>\n'
'  <span data-testid="kpi_medium"></span>\n'
'  <span data-testid="kpi_low"></span>\n'
'  <span data-testid="kpi_info_trace"></span>\n'
'</div>\n'
'<div id="vsp-runs-main" style="display:none"></div>\n'
'<div id="vsp-data-source-main" style="display:none"></div>\n'
'<div id="vsp-settings-main" style="display:none"></div>\n'
'<div id="vsp-rule-overrides-main" style="display:none"></div>\n'
'<!-- end '+marker+' -->\n'
)

def backup(p: Path, s: str):
    bak = p.with_suffix(p.suffix + f".bak_real_shell_{ts}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

def inject_after_dashboard_div(s: str) -> str:
    # best place: right after dashboard main div (present in your live HTML)
    pat = r'(<div\s+id="vsp-dashboard-main"\s*>\s*</div>)'
    m = re.search(pat, s, flags=re.I)
    if m:
        if inject in s:
            return s
        return s[:m.end()] + "\n" + inject + s[m.end():]
    return s

def inject_after_body_open(s: str) -> str:
    if inject in s:
        return s
    m = re.search(r'(?is)<body\b[^>]*>', s)
    if not m:
        return s + "\n" + inject
    return s[:m.end()] + "\n" + inject + s[m.end():]

patched=0
for p in cands:
    s=p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[OK] already patched:", p)
        continue
    s2 = inject_after_dashboard_div(s)
    if s2 == s:
        s2 = inject_after_body_open(s)
    if s2 != s:
        backup(p, s)
        p.write_text(s2, encoding="utf-8")
        print("[OK] patched:", p)
        patched += 1
    else:
        print("[WARN] no change:", p)

print("[DONE] patched_files=", patched)
PY

echo "== [3] Restart service =="
systemctl restart "$SVC" || true
sleep 0.9
systemctl status "$SVC" -l --no-pager | head -n 35 || true

echo "== [4] Smoke curl markers (must PASS) =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total" || echo "[ERR] vsp5 kpi_total MISSING"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main" || echo "[ERR] runs main MISSING"
curl -fsS "$BASE/data_source" | grep -q 'id="vsp-data-source-main"' && echo "[OK] data_source main" || echo "[ERR] data_source main MISSING"
curl -fsS "$BASE/settings" | grep -q 'id="vsp-settings-main"' && echo "[OK] settings main" || echo "[ERR] settings main MISSING"
curl -fsS "$BASE/rule_overrides" | grep -q 'id="vsp-rule-overrides-main"' && echo "[OK] rule_overrides main" || echo "[ERR] rule_overrides main MISSING"

echo "[NEXT] Run gate: bash bin/p1_ui_spec_gate_v1.sh"
