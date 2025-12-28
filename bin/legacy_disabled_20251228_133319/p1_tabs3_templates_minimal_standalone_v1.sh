#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need wc

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time

ts = int(time.time())

def write_min(p: Path, title: str, tab: str, js_common: str, js_tab: str):
    html = f'''<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>{title}</title>

  <!-- keep commercial dark theme -->
  <link rel="stylesheet" href="/static/css/vsp_dark_commercial_p1_2.css"/>

  <!-- force dark background even if css missing -->
  <style id="VSP_TABS3_FORCE_DARK_BG_V1">
    html,body{{background:#070e1a;color:#e5e7eb; margin:0;}}
  </style>
</head>
<body>
  <div id="vsp_tab_root" data-vsp-tab="{tab}" style="padding:16px">
    <div style="color:#94a3b8;font-size:12px">Loading...</div>
  </div>

  <!-- Load ONLY v3 scripts (no bundle/topbar/global poll; no Jinja vars) -->
  <script src="/{js_common}?v={ts}"></script>
  <script src="/{js_tab}?v={ts}"></script>
</body>
</html>
'''
    p.write_text(html, encoding="utf-8")

targets = [
  ("templates/vsp_data_source_2025.html", "VSP • Data Source", "data_source",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_data_source_tab_v3.js"),
  ("templates/vsp_settings_2025.html", "VSP • Settings", "settings",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_settings_tab_v3.js"),
  ("templates/vsp_rule_overrides_2025.html", "VSP • Rule Overrides", "rule_overrides",
   "static/js/vsp_tabs3_common_v3.js", "static/js/vsp_rule_overrides_tab_v3.js"),
]

stamp = time.strftime("%Y%m%d_%H%M%S")
for fp, title, tab, cjs, tjs in targets:
    p = Path(fp)
    if not p.exists():
        print("[ERR] missing", p)
        continue
    bak = p.with_name(p.name + f".bak_min_{stamp}")
    bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[BACKUP]", bak)
    write_min(p, title, tab, cjs, tjs)
    print("[OK] wrote minimal", p)

print("[DONE] minimal templates ready")
PY

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.0

echo "== verify HTML shows ONLY v3 =="
for p in data_source settings rule_overrides; do
  echo "--- $p scripts"
  curl -fsS "http://127.0.0.1:8910/$p" | egrep -n 'vsp_bundle|vsp_topbar|GLOBAL_POLL|asset_v|tabs3_common_v2|_tab_v2|_tab_v1' | head -n 10 || echo "[OK] no legacy/bundle"
  curl -fsS "http://127.0.0.1:8910/$p" | egrep -n 'vsp_tabs3_common_v3|vsp_.*_tab_v3|vsp_tab_root' | head -n 10
done

echo "== verify JS bytes non-zero =="
for f in vsp_tabs3_common_v3.js vsp_data_source_tab_v3.js vsp_settings_tab_v3.js vsp_rule_overrides_tab_v3.js; do
  echo -n "$f bytes="; curl -fsS "http://127.0.0.1:8910/static/js/$f" | wc -c
done

echo "[OK] minimal standalone applied"
