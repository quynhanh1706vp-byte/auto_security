#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

TS="$(date +%Y%m%d_%H%M%S)"

JS="static/js/vsp_dashboard_gate_story_v1.js"
PANELS="static/js/vsp_dashboard_commercial_panels_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$PANELS" ] || { echo "[ERR] missing $PANELS (run previous script step2 first)"; exit 2; }

cp -f "$JS" "${JS}.bak_disable_p1_${TS}"
echo "[BACKUP] ${JS}.bak_disable_p1_${TS}"

echo "== [1/3] Disable all injected P1 panels blocks inside GateStory JS (remove marker blocks) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove any blocks that were appended with markers:
#   /* ===================== VSP_P1_DASHBOARD_P1_PANELS_.... =====================
#   ...
#   /* ===================== /VSP_P1_DASHBOARD_P1_PANELS_.... ===================== */
#
# This wipes V1..V7 piles safely.
pat = re.compile(
    r"/\*\s*====================\s*VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?"
    r"/\*\s*====================\s*/VSP_P1_DASHBOARD_P1_PANELS_[\s\S]*?\*/\s*",
    re.M
)

s2, n = pat.subn("", s)
# Also remove any stray “DashP1Vx” debug blocks if they exist without markers
pat2 = re.compile(r"/\*\s*\[DashP1V[0-9]+\][\s\S]*?\*/\s*", re.M)
s2, n2 = pat2.subn("", s2)

p.write_text(s2, encoding="utf-8")
print(f"[OK] removed blocks: marker_blocks={n}, stray_dashp1_blocks={n2}")
PY

if [ "$node_ok" = "1" ]; then
  node --check "$JS" && echo "[OK] node --check GateStory OK after disable"
else
  echo "[WARN] node not found; skip syntax check"
fi

echo "== [2/3] Find the REAL HTML template that includes vsp_dashboard_gate_story_v1.js and patch it =="

python3 - <<'PY'
from pathlib import Path
import re, time

needle = "vsp_dashboard_gate_story_v1.js"
root = Path(".")
cands = []

# search templates first (most likely)
for p in (root/"templates").rglob("*.html"):
    if ".bak_" in p.name: 
        continue
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if needle in txt:
        cands.append(p)

# fallback: search python files that might embed HTML
if not cands:
    for p in root.rglob("*.py"):
        if any(x in p.parts for x in ("out_ci","bin","node_modules")): 
            continue
        if ".bak_" in p.name:
            continue
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if needle in txt and "vsp5" in txt:
            cands.append(p)

if not cands:
    print("[ERR] cannot find any file that includes vsp_dashboard_gate_story_v1.js")
    raise SystemExit(2)

# pick the most likely: shortest path + templates preferred
cands = sorted(cands, key=lambda p: (0 if "templates" in p.parts else 1, len(str(p))))
target = cands[0]
ts = time.strftime("%Y%m%d_%H%M%S")

txt = target.read_text(encoding="utf-8", errors="replace")
bak = target.with_name(target.name + f".bak_panels_{ts}")
bak.write_text(txt, encoding="utf-8")

marker = "VSP_P1_DASHCOMM_PANELS_V1_TEMPLATE_INCLUDE"
if marker in txt or "vsp_dashboard_commercial_panels_v1.js" in txt:
    print(f"[OK] panels already included in {target}")
    raise SystemExit(0)

# patch: after the GateStory script tag; keep same ?v=... if present
# matches both ?v={{ asset_v }} and ?v=12345 or no query
pat = re.compile(r'(<script[^>]+src="/static/js/vsp_dashboard_gate_story_v1\.js(?:\?v=([^"]+))?"[^>]*></script>)')

m = pat.search(txt)
if not m:
    print(f"[ERR] cannot find script tag in {target} even though needle exists")
    raise SystemExit(2)

v = m.group(2)
if v:
    ins = f'{m.group(1)}\n  <!-- {marker} -->\n  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js?v={v}"></script>'
else:
    ins = f'{m.group(1)}\n  <!-- {marker} -->\n  <script src="/static/js/vsp_dashboard_commercial_panels_v1.js"></script>'

txt2 = pat.sub(ins, txt, count=1)
target.write_text(txt2, encoding="utf-8")

print(f"[OK] patched template: {target}")
print(f"[OK] backup saved: {bak}")
PY

echo "== [3/3] Quick verify HTML now includes panels script =="
BASE="http://127.0.0.1:8910"
curl -fsS "$BASE/vsp5" | grep -nE "vsp_dashboard_gate_story_v1\.js|vsp_dashboard_commercial_panels_v1\.js" | head -n 20 || true

echo
echo "[DONE] Now do:"
echo "  1) restart UI (systemd/gunicorn)"
echo "  2) Ctrl+Shift+R /vsp5"
