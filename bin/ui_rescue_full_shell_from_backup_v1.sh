#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_before_rescue_${TS}"
echo "[BACKUP] $TPL.bak_before_rescue_${TS}"

python3 - <<'PY'
from pathlib import Path
import glob, os, time

tpl = Path("templates/vsp_dashboard_2025.html")
cur = tpl.read_text(encoding="utf-8", errors="ignore")

need_tokens = ["Runs", "Data Source", "Settings", "Rule Overrides"]
def looks_full(html: str) -> bool:
    # heuristic: phải có ít nhất 2/4 token tab
    hit = sum(1 for t in need_tokens if t in html)
    return hit >= 2

picked = None
if looks_full(cur):
    print("[OK] current template already looks full (has tabs). No restore needed.")
else:
    cands = sorted(glob.glob("templates/vsp_dashboard_2025.html.bak_*"), key=lambda p: os.path.getmtime(p), reverse=True)
    for c in cands:
        h = Path(c).read_text(encoding="utf-8", errors="ignore")
        if looks_full(h):
            picked = c
            break
    if not picked:
        raise SystemExit("[ERR] cannot find any backup with full shell (tabs).")
    tpl.write_text(Path(picked).read_text(encoding="utf-8", errors="ignore"), encoding="utf-8")
    print("[RESTORE] template <= ", picked)

# ensure hash normalizer in <head>
html = tpl.read_text(encoding="utf-8", errors="ignore")
if "vsp_hash_normalize_v1.js" not in html:
    tag = f'<script src="/static/js/vsp_hash_normalize_v1.js?v={int(time.time())}"></script>'
    i = html.lower().find("<head")
    if i >= 0:
        j = html.find(">", i)
        html = html[:j+1] + "\n  " + tag + "\n" + html[j+1:]
    else:
        html = tag + "\n" + html
    print("[OK] injected hash normalizer tag")

# ensure loader + features before </body>
ins = f'\n  <script src="/static/js/vsp_ui_features_v1.js?v={int(time.time())}"></script>\n' \
      f'  <script src="/static/js/vsp_ui_loader_route_v1.js?v={int(time.time())}"></script>\n'
if "vsp_ui_loader_route_v1.js" not in html:
    if "</body>" in html:
        html = html.replace("</body>", ins + "</body>")
    else:
        html += ins
    print("[OK] injected route loader tags")

tpl.write_text(html, encoding="utf-8")
print("[OK] template ready")
PY

echo "== restart 8910 (NO restore) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "== verify /vsp4 has tabs + loader tags =="
HTML="$(curl -sS http://127.0.0.1:8910/vsp4 || true)"
echo "$HTML" | grep -q "vsp_ui_loader_route_v1.js" && echo "[OK] loader present" || echo "[WARN] loader missing in /vsp4"
echo "$HTML" | grep -Eiq "Runs|Data Source|Settings|Rule Overrides" && echo "[OK] tabs present" || echo "[WARN] tabs missing in /vsp4"

echo
echo "[NEXT] Mở đúng URL: http://127.0.0.1:8910/vsp4/#dashboard"
echo "       Và thử:      http://127.0.0.1:8910/vsp4/#datasource"
