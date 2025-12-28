#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time, re

tpls = [
  ("templates/vsp_data_source_2025.html",  ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_data_source_tab_v3.js"]),
  ("templates/vsp_settings_2025.html",     ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_settings_tab_v3.js"]),
  ("templates/vsp_rule_overrides_2025.html",["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_rule_overrides_tab_v3.js"]),
]

ts = time.strftime("%Y%m%d_%H%M%S")

for fp, scripts in tpls:
    p = Path(fp)
    if not p.exists():
        print("[ERR] missing", p)
        continue

    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_harden_{ts}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    # 1) fix escaped quotes:  rel=\"stylesheet\"  -> rel="stylesheet"
    s2 = s.replace('\\"', '"')

    # 2) ensure root mount
    if 'id="vsp_tab_root"' not in s2:
        # put near top of body
        if re.search(r"<body[^>]*>", s2, flags=re.I):
            s2 = re.sub(r"(<body[^>]*>)", r"\1\n<div id=\"vsp_tab_root\" style=\"padding:16px\"></div>\n", s2, flags=re.I, count=1)
        else:
            s2 += '\n<div id="vsp_tab_root" style="padding:16px"></div>\n'

    # 3) force include scripts before </body>
    for sc in scripts:
        tag = f'/'+sc
        if tag not in s2:
            ins = f'<script src="/{sc}?v={int(time.time())}"></script>\n'
            if "</body>" in s2:
                s2 = s2.replace("</body>", ins + "</body>")
            else:
                s2 += "\n" + ins

    p.write_text(s2, encoding="utf-8")
    print("[OK] hardened", p)

PY

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.0

echo "== verify templates include root+scripts =="
for p in data_source settings rule_overrides; do
  echo "--- /$p grep root/scripts"
  curl -fsS "http://127.0.0.1:8910/$p" | egrep -n 'vsp_tab_root|vsp_tabs3_common_v3|vsp_.*_tab_v3' | head -n 20 || true
done

echo "[OK] templates hardened"
