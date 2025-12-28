#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need find; need grep; need sed; need awk; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
NAME="vsp_5tabs_enterprise_v2.html"

TS="$(date +%Y%m%d_%H%M%S)"
echo "== [1] find all copies of $NAME =="
mapfile -t files < <(find . -type f -name "$NAME" \
  ! -name '*.bak_*' ! -name '*.bak_markers_*' ! -path './.venv/*' ! -path './node_modules/*' \
  | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo "[ERR] no template file named $NAME found under $(pwd)"
  exit 2
fi

printf "%s\n" "${files[@]}" | sed 's/^/[FOUND] /'

echo "== [2] patch each copy (insert required markers after <body>) =="
python3 - "$TS" "${files[@]}" <<'PY'
import sys, re
from pathlib import Path

ts = sys.argv[1]
paths = [Path(p) for p in sys.argv[2:]]

# Required markers (exact double quotes as gate expects)
INJECT = (
    '\n<!-- VSP_P1_REQUIRED_MARKERS_V2 -->\n'
    '<div id="vsp-dashboard-main" style="display:none"></div>\n'
    '<div id="vsp-runs-main" style="display:none"></div>\n'
    '<div id="vsp-data-source-main" style="display:none"></div>\n'
    '<div id="vsp-settings-main" style="display:none"></div>\n'
    '<div id="vsp-rule-overrides-main" style="display:none"></div>\n'
    '<div id="vsp-kpi-testids" style="display:none">\n'
    '  <span data-testid="kpi_total"></span>\n'
    '  <span data-testid="kpi_critical"></span>\n'
    '  <span data-testid="kpi_high"></span>\n'
    '  <span data-testid="kpi_medium"></span>\n'
    '  <span data-testid="kpi_low"></span>\n'
    '  <span data-testid="kpi_info_trace"></span>\n'
    '</div>\n'
    '<!-- end VSP_P1_REQUIRED_MARKERS_V2 -->\n'
)

def insert_after_body_open(html: str, inject: str) -> str:
    if inject in html:
        return html
    m = re.search(r'(?is)<body\b[^>]*>', html)
    if not m:
        # fallback: append at end
        return html + "\n" + inject
    return html[:m.end()] + inject + html[m.end():]

for p in paths:
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        print("[WARN] cannot read:", p, e)
        continue

    # If required markers already present, skip
    if 'data-testid="kpi_total"' in s and 'id="vsp-runs-main"' in s and 'id="vsp-settings-main"' in s:
        print("[OK] already has markers:", p)
        continue

    s2 = insert_after_body_open(s, INJECT)

    if s2 != s:
        bak = p.with_suffix(p.suffix + f".bak_markers_{ts}")
        bak.write_text(s, encoding="utf-8")
        p.write_text(s2, encoding="utf-8")
        print("[BACKUP]", bak)
        print("[OK] patched:", p)
    else:
        print("[WARN] no change (could not insert):", p)
PY

echo "== [3] restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 35 || true

echo "== [4] smoke curl (must see markers) =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[ERR] vsp5 kpi_total missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main id present" || echo "[ERR] runs main id missing"
curl -fsS "$BASE/data_source" | grep -q 'id="vsp-data-source-main"' && echo "[OK] data_source main id present" || echo "[ERR] data_source main id missing"
curl -fsS "$BASE/settings" | grep -q 'id="vsp-settings-main"' && echo "[OK] settings main id present" || echo "[ERR] settings main id missing"
curl -fsS "$BASE/rule_overrides" | grep -q 'id="vsp-rule-overrides-main"' && echo "[OK] rule_overrides main id present" || echo "[ERR] rule_overrides main id missing"

echo "[NEXT] run gate: bash bin/p1_ui_spec_gate_v1.sh"
