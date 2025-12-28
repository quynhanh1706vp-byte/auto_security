#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

echo "== check loader tags in template =="
grep -n "vsp_ui_loader_route_v1.js" "$TPL" || true
grep -n "vsp_ui_features_v1.js" "$TPL" || true

if ! grep -q "vsp_ui_loader_route_v1.js" "$TPL"; then
  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$TPL" "$TPL.bak_fix_loader_${TS}"
  echo "[BACKUP] $TPL.bak_fix_loader_${TS}"

  python3 - <<'PY'
from pathlib import Path
p=Path("templates/vsp_dashboard_2025.html")
html=p.read_text(encoding="utf-8", errors="ignore")
ins = "\n  <script src=\"/static/js/vsp_ui_features_v1.js?v=FIX\"></script>\n" \
      "  <script src=\"/static/js/vsp_ui_loader_route_v1.js?v=FIX\"></script>\n"
if "vsp_ui_loader_route_v1.js" in html:
    print("[OK] already has loader")
else:
    if "</body>" in html:
        html = html.replace("</body>", ins + "</body>")
    else:
        html += ins
    p.write_text(html, encoding="utf-8")
    print("[OK] injected loader tags into template")
PY
fi

echo "== restart 8910 (NO restore snapshot) =="
bash bin/ui_restart_8910_no_restore_v1.sh

echo "== verify /vsp4 contains loader =="
curl -sS http://127.0.0.1:8910/vsp4 | grep -n "vsp_ui_loader_route_v1.js" || {
  echo "[ERR] /vsp4 still missing loader => /vsp4 may be serving a DIFFERENT template";
  echo "== hint: search vsp4 route mapping =="
  grep -RIn "vsp4" . | head -n 40 || true
  exit 3
}

echo "[OK] loader present in /vsp4"
