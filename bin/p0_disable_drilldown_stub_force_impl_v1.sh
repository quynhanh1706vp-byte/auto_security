#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

IMPL="/static/js/vsp_drilldown_artifacts_impl_commercial_v1.js?v=${TS}"
MARK="VSP_FORCE_DRILLDOWN_IMPL_P0_V1"

python3 - <<PY
from pathlib import Path
import re

tpl_dir = Path("templates")
hits = 0

for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="ignore")

    if "vsp_drilldown_stub_safe_v1.js" in s:
        # backup once per file
        (p.parent / (p.name + f".bak_disable_stub_{TS}")).write_text(s, encoding="utf-8")
        # comment out any script tag loading the stub
        s2 = re.sub(r'(?is)<script[^>]+vsp_drilldown_stub_safe_v1\.js[^>]*>\s*</script>',
                    r'<!-- disabled: vsp_drilldown_stub_safe_v1.js (P0) -->', s)
        s = s2
        hits += 1
        p.write_text(s, encoding="utf-8")
        print("[OK] disabled stub in", p)

# Force-load impl in main dashboard template if present (idempotent)
main = Path("templates/vsp_dashboard_2025.html")
if main.exists():
    s = main.read_text(encoding="utf-8", errors="ignore")
    if MARK not in s:
        # insert impl script before loader script if found, else before </head>, else prepend
        ins = f"<!-- {MARK} -->\\n<script src='{IMPL}'></script>\\n"
        if "vsp_ui_loader_route" in s:
            s = re.sub(r'(?is)(<script[^>]+vsp_ui_loader_route[^>]*></script>)',
                       ins + r"\\1", s, count=1)
        elif "</head>" in s.lower():
            s = re.sub(r'(?is)</head>', ins + "</head>", s, count=1)
        else:
            s = ins + s
        main.write_text(s, encoding="utf-8")
        print("[OK] forced impl load in", main)
    else:
        print("[OK] impl already forced in", main)
else:
    print("[WARN] templates/vsp_dashboard_2025.html missing; skip force-impl insert")

print("[OK] templates processed. stub_hits=", hits)
PY

echo "[OK] done"
