#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TPL="templates/vsp_runs_reports_v1.html"
MARK="VSP_P1_RUNS_TEMPLATE_REMOVE_DATARID_JINJA_V1B"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_dataridfix_${TS}"
echo "[BACKUP] ${TPL}.bak_dataridfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("templates/vsp_runs_reports_v1.html")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_RUNS_TEMPLATE_REMOVE_DATARID_JINJA_V1B"
if mark in s:
    print("[OK] already patched:", mark)
    raise SystemExit(0)

# 1) Remove the known offender: data-rid="{{ ... }}"
s2, n1 = re.subn(r'data-rid="\{\{[^}]*\}\}"', 'data-rid=""', s)

# 2) Hard-clean any leftover Jinja tokens in this template (commercial smoke-safe)
#    (Only touches HTML template; JS behavior remains.)
s3, n2 = re.subn(r"\{\{[^}]*\}\}", "", s2)

p.write_text(f"<!-- {mark} datarid={n1} clean={{}}={n2} -->\n" + s3, encoding="utf-8")
print("[OK] patched:", mark, "datarid_replaced=", n1, "leftover_tokens_removed=", n2)
PY

systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
echo "[DONE] runs template cleaned (no {{...}})."
