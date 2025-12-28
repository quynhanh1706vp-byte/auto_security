#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<PY
from pathlib import Path
import re

TS = "${TS}"
IMPL_SRC = f"/static/js/vsp_drilldown_artifacts_impl_commercial_v1.js?v={TS}"
MARK = "VSP_FORCE_DRILLDOWN_IMPL_P0_V2"

tpl_dir = Path("templates")
hits = 0

# 1) disable any script tag that loads vsp_drilldown_stub_safe_v1.js
for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")
    if "vsp_drilldown_stub_safe_v1.js" not in s:
        continue
    bak = p.with_suffix(p.suffix + f".bak_disable_stub_{TS}")
    bak.write_text(s, encoding="utf-8")
    s2 = re.sub(r'(?is)<script[^>]+vsp_drilldown_stub_safe_v1\.js[^>]*>\s*</script>',
                r'<!-- disabled: vsp_drilldown_stub_safe_v1.js (P0) -->', s)
    p.write_text(s2, encoding="utf-8")
    hits += 1
    print("[OK] disabled stub in", p)

# 2) force-load commercial impl in main dashboard template (best-effort)
main = Path("templates/vsp_dashboard_2025.html")
if main.exists():
    s = main.read_text(encoding="utf-8", errors="ignore")
    if MARK not in s:
        ins = f"<!-- {MARK} -->\\n<script src='{IMPL_SRC}'></script>\\n"
        if "vsp_ui_loader_route" in s:
            # insert BEFORE first loader script tag
            s = re.sub(r'(?is)(<script[^>]+vsp_ui_loader_route[^>]*></script>)',
                       ins + r"\\1", s, count=1)
        elif re.search(r'(?is)</head>', s):
            s = re.sub(r'(?is)</head>', ins + "</head>", s, count=1)
        else:
            s = ins + s
        main.write_text(s, encoding="utf-8")
        print("[OK] forced impl load in", main)
    else:
        print("[OK] impl already forced in", main)
else:
    print("[WARN] templates/vsp_dashboard_2025.html missing; skip force-impl insert")

print("[OK] templates processed stub_hits=", hits)
PY

echo "[OK] done"
