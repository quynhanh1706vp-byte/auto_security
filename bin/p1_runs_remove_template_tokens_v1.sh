#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TPL="templates/vsp_runs_reports_v1.html"
MARK="VSP_P1_RUNS_REMOVE_TEMPLATE_TOKENS_V1"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_notokens_${TS}"
echo "[BACKUP] ${TPL}.bak_notokens_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_RUNS_REMOVE_TEMPLATE_TOKENS_V1"

if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# Replace any ?v={{ ... }} (any whitespace/filters) with nothing
s2, n = re.subn(r'\?v=\{\{[^}]*\}\}', '', s)

# Also remove stray '{{' tokens in HTML comments or attrs (rare) by neutralizing ONLY inside src/href attributes:
# (keep minimal and safe; most issues are v={{...}})
tpl.write_text(f"<!-- {mark} -->\n" + s2, encoding="utf-8")
print("[OK] removed v={{...}} tokens n=", n)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] /runs template tokens removed."
