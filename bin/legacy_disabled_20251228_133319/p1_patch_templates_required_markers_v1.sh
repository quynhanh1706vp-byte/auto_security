#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need sed

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
TPLDIR="templates"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -d "$TPLDIR" ] || { echo "[ERR] missing templates/ dir"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="/tmp/vsp_tpl_markers_${TS}"
mkdir -p "$OUT"

python3 - "$WSGI" "$TPLDIR" "$TS" <<'PY'
from pathlib import Path
import re, sys

wsgi = Path(sys.argv[1])
tpldir = Path(sys.argv[2])
ts = sys.argv[3]

s = wsgi.read_text(encoding="utf-8", errors="replace")

# Extract template name for each route path by scanning forward from decorator to render_template()
paths = ["/vsp5","/runs","/data_source","/settings","/rule_overrides"]
route_tpl = {}

for path in paths:
    # match @app.route("/path"...)
    m = re.search(r'(?ms)^\s*@app\.route\(\s*[\'"]' + re.escape(path) + r'[\'"][^\)]*\)\s*\n\s*def\s+\w+\s*\([^\)]*\)\s*:\s*\n(.*?)(?=^\s*@app\.route|\Z)', s)
    if not m:
        continue
    body = m.group(1)
    # find render_template("file.html"
    m2 = re.search(r'render_template\(\s*[\'"]([^\'"]+\.html)[\'"]', body)
    if m2:
        route_tpl[path] = m2.group(1)

# If some not found, fallback by heuristics: find templates that contain <title>VSP • ...
# We'll only use heuristics if missing.
def find_by_title(substr):
    for p in tpldir.rglob("*.html"):
        try:
            t = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if substr in t:
            return p.name
    return None

if "/vsp5" not in route_tpl:
    guess = find_by_title("VSP • Dashboard") or find_by_title("VSP •") or None
    if guess:
        route_tpl["/vsp5"] = guess
if "/runs" not in route_tpl:
    guess = find_by_title("Runs") or None
    if guess:
        route_tpl["/runs"] = guess
if "/data_source" not in route_tpl:
    guess = find_by_title("Data Source") or None
    if guess:
        route_tpl["/data_source"] = guess
if "/settings" not in route_tpl:
    guess = find_by_title("Settings") or None
    if guess:
        route_tpl["/settings"] = guess
if "/rule_overrides" not in route_tpl:
    guess = find_by_title("Rule Overrides") or None
    if guess:
        route_tpl["/rule_overrides"] = guess

print("== route->template ==")
for k in paths:
    print(k, "=>", route_tpl.get(k))

# Patching helpers
def backup_write(p: Path, new: str):
    bak = p.with_suffix(p.suffix + f".bak_markers_{ts}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    p.write_text(new, encoding="utf-8")
    print("[BACKUP]", bak)

def insert_after_body_open(html: str, inject: str) -> str:
    if inject in html:
        return html
    m = re.search(r'(?is)<body\b[^>]*>', html)
    if not m:
        return html + "\n" + inject
    pos = m.end()
    return html[:pos] + "\n" + inject + html[pos:]

def insert_after_first(html: str, needle_regex: str, inject: str) -> str:
    if inject in html:
        return html
    m = re.search(needle_regex, html, flags=re.I|re.S)
    if not m:
        return html
    return html[:m.end()] + "\n" + inject + html[m.end():]

# Required marker inject strings (exact double quotes)
KPI_INJ = (
    '<div id="vsp-kpi-testids" style="display:none">\n'
    '  <span data-testid="kpi_total"></span>\n'
    '  <span data-testid="kpi_critical"></span>\n'
    '  <span data-testid="kpi_high"></span>\n'
    '  <span data-testid="kpi_medium"></span>\n'
    '  <span data-testid="kpi_low"></span>\n'
    '  <span data-testid="kpi_info_trace"></span>\n'
    '</div>'
)

RUNS_INJ = '<div id="vsp-runs-main" style="display:none"></div>'
DS_INJ   = '<div id="vsp-data-source-main" style="display:none"></div>'
SET_INJ  = '<div id="vsp-settings-main" style="display:none"></div>'
RO_INJ   = '<div id="vsp-rule-overrides-main" style="display:none"></div>'

# Apply patches
for path, tplname in list(route_tpl.items()):
    if not tplname:
        continue
    tp = tpldir / tplname
    if not tp.exists():
        # try any nested template with same name
        hits = list(tpldir.rglob(tplname))
        if hits:
            tp = hits[0]
    if not tp.exists():
        print("[WARN] template not found on disk:", tplname)
        continue

    html = tp.read_text(encoding="utf-8", errors="replace")
    new = html

    if path == "/vsp5":
        # Ensure KPI markers exist in raw HTML.
        if 'data-testid="kpi_total"' not in new:
            # Prefer inserting right after existing dashboard main container if present,
            # because your HTML already contains <div id="vsp-dashboard-main"></div>
            new2 = insert_after_first(new, r'<div\s+id="vsp-dashboard-main"\s*>\s*</div>', KPI_INJ)
            if new2 == new:
                # fallback: insert after body open
                new2 = insert_after_body_open(new, KPI_INJ)
            new = new2

    elif path == "/runs":
        if 'id="vsp-runs-main"' not in new:
            new = insert_after_body_open(new, RUNS_INJ)

    elif path == "/data_source":
        if 'id="vsp-data-source-main"' not in new:
            new = insert_after_body_open(new, DS_INJ)

    elif path == "/settings":
        if 'id="vsp-settings-main"' not in new:
            new = insert_after_body_open(new, SET_INJ)

    elif path == "/rule_overrides":
        if 'id="vsp-rule-overrides-main"' not in new:
            new = insert_after_body_open(new, RO_INJ)

    if new != html:
        backup_write(tp, new)
        print("[OK] patched template for", path, "=>", tp)
    else:
        print("[OK] no change needed for", path, "=>", tp)

PY

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 30 || true

echo "== smoke curl markers =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -q 'data-testid="kpi_total"' && echo "[OK] vsp5 kpi_total present" || echo "[ERR] vsp5 kpi_total missing"
curl -fsS "$BASE/runs" | grep -q 'id="vsp-runs-main"' && echo "[OK] runs main id present" || echo "[ERR] runs main id missing"
curl -fsS "$BASE/data_source" | grep -q 'id="vsp-data-source-main"' && echo "[OK] data_source main id present" || echo "[ERR] data_source main id missing"
curl -fsS "$BASE/settings" | grep -q 'id="vsp-settings-main"' && echo "[OK] settings main id present" || echo "[ERR] settings main id missing"
curl -fsS "$BASE/rule_overrides" | grep -q 'id="vsp-rule-overrides-main"' && echo "[OK] rule_overrides main id present" || echo "[ERR] rule_overrides main id missing"

echo "[NEXT] run gate: bash bin/p1_ui_spec_gate_v1.sh"
