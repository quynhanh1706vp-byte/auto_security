#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

targets = [
  ("templates/vsp_data_source_2025.html",
   ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_data_source_tab_v3.js"]),
  ("templates/vsp_settings_2025.html",
   ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_settings_tab_v3.js"]),
  ("templates/vsp_rule_overrides_2025.html",
   ["static/js/vsp_tabs3_common_v3.js", "static/js/vsp_rule_overrides_tab_v3.js"]),
]

ts = time.strftime("%Y%m%d_%H%M%S")

def drop_tag(s, pattern):
    return re.sub(pattern, "", s, flags=re.I|re.M)

for fp, keep_scripts in targets:
    p = Path(fp)
    if not p.exists():
        print("[ERR] missing", p)
        continue

    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_cleanlegacy_{ts}")
    bak.write_text(s, encoding="utf-8")
    print("[BACKUP]", bak)

    # 0) normalize escaped quotes if any
    s2 = s.replace('\\"', '"')

    # 1) Remove legacy v1/v2 scripts for tabs + common
    legacy_patterns = [
        r'^\s*<script[^>]+/static/js/vsp_data_source_tab_v1\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_data_source_tab_v2\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_settings_tab_v2\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_rule_overrides_tab_v1\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_rule_overrides_tab_v2\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_tabs3_common_v2\.js[^>]*>\s*</script>\s*$',
        r'^\s*<script[^>]+/static/js/vsp_tabs3_common_v1\.js[^>]*>\s*</script>\s*$',
    ]
    for pat in legacy_patterns:
        s2 = drop_tag(s2, pat)

    # 2) (Optional but recommended) Remove legacy v1 css for data_source (it can make page white)
    s2 = re.sub(r'^\s*<link[^>]+/static/css/vsp_data_source_tab_v1\.css[^>]*>\s*$', "", s2, flags=re.I|re.M)

    # 3) Ensure vsp_tab_root exists
    if 'id="vsp_tab_root"' not in s2:
        if re.search(r"<body[^>]*>", s2, flags=re.I):
            s2 = re.sub(r"(<body[^>]*>)", r"\1\n<div id=\"vsp_tab_root\" style=\"padding:16px\"></div>\n", s2, flags=re.I, count=1)
        else:
            s2 += '\n<div id="vsp_tab_root" style="padding:16px"></div>\n'

    # 4) Ensure dark background regardless of css
    if "VSP_TABS3_FORCE_DARK_BG_V1" not in s2:
        inject = '<style id="VSP_TABS3_FORCE_DARK_BG_V1">html,body{background:#070e1a;color:#e5e7eb;}</style>\n'
        if "</head>" in s2:
            s2 = s2.replace("</head>", inject + "</head>")
        else:
            s2 = inject + s2

    # 5) Remove duplicated keep scripts then re-add clean (exactly once)
    for sc in keep_scripts:
        s2 = re.sub(r'^\s*<script[^>]+src="/' + re.escape(sc) + r'[^"]*"[^>]*>\s*</script>\s*$', "", s2, flags=re.I|re.M)

    # insert scripts near end of body
    block = ""
    for sc in keep_scripts:
        block += f'<script src="/{sc}?v={int(time.time())}"></script>\n'

    if "</body>" in s2:
        s2 = s2.replace("</body>", block + "</body>")
    else:
        s2 += "\n" + block

    p.write_text(s2, encoding="utf-8")
    print("[OK] cleaned =>", p)

print("[DONE] clean legacy + keep v3 only")
PY

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 1.0

echo "== verify ONLY v3 scripts remain =="
for p in data_source settings rule_overrides; do
  echo "--- $p"
  curl -fsS "http://127.0.0.1:8910/$p" | egrep -n 'vsp_.*_tab_v[12]|vsp_tabs3_common_v[12]' | head -n 20 || echo "[OK] no legacy v1/v2"
  curl -fsS "http://127.0.0.1:8910/$p" | egrep -n 'vsp_tabs3_common_v3|vsp_.*_tab_v3|vsp_tab_root' | head -n 20 || true
done

echo "== quick API sanity (must be ok:true) =="
curl -fsS "http://127.0.0.1:8910/api/ui/findings_v2?limit=1&offset=0" | head -c 200; echo
curl -fsS "http://127.0.0.1:8910/api/ui/settings_v2" | head -c 120; echo
curl -fsS "http://127.0.0.1:8910/api/ui/rule_overrides_v2" | head -c 140; echo

echo "[OK] cleaned"
