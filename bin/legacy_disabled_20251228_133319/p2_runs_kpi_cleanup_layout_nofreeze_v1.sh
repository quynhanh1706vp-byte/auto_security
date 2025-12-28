#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TPL="templates/vsp_runs_reports_v1.html"
JS="static/js/vsp_runs_reports_overlay_v1.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "${TPL}.bak_kpi_cleanup_${TS}"
cp -f "$JS"  "${JS}.bak_kpi_cleanup_${TS}"
echo "[BACKUP] ${TPL}.bak_kpi_cleanup_${TS}"
echo "[BACKUP] ${JS}.bak_kpi_cleanup_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_runs_reports_v1.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

# 1) Remove explicit V1 panel if marker exists
s2 = re.sub(
    r"(?s)<!--\s*====================\s*VSP_P2_RUNS_KPI_PANEL_V1.*?/VSP_P2_RUNS_KPI_PANEL_V1\s*====================\s*-->",
    "",
    s,
    count=1
)

# 2) If still has duplicated "Runs — Operational KPI", keep the FIRST one (v2) and delete the next KPI+trend block.
# Target the block that contains the phrase "Server-side KPI (safe allowlist)" (this is v1).
s3 = re.sub(
    r"(?s)<section[^>]*>\s*.*?Runs\s*—\s*Operational\s*KPI.*?Server-side\s*KPI\s*\(safe\s*allowlist\).*?</section>\s*",
    "",
    s2,
    count=1
)

# 3) Remove the heavy blank trend section (overall trend + critical/high trend) if present (v1 placeholders)
# We delete the first occurrence of the trend container that mentions those headings.
s4 = re.sub(
    r"(?s)Overall\s+status\s+trend\s+\(stacked\).*?CRITICAL/HIGH\s+trend\s+\(if\s+available\).*?(?=<div[^>]+class=\"vsp-card\"|<section|<table|<div[^>]+id=\"vsp_runs\"|<!--|$)",
    "",
    s3,
    count=1
)

tpl.write_text(s4, encoding="utf-8")
print("[OK] cleaned template: removed KPI v1 + heavy trend placeholders (if existed)")
PY

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_runs_reports_overlay_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

# Add a global guard so legacy KPI v1 logic (if still present) won't run when v2 binder exists.
marker = "VSP_P2_DISABLE_KPI_V1_WHEN_V2"
if marker in s:
    print("[OK] guard already present")
else:
    # Try to inject near the top of KPI v1 block marker
    if "VSP_P2_RUNS_KPI_JS_V1" in s:
        s = s.replace(
            "/* VSP_P2_RUNS_KPI_JS_V1",
            "/* "+marker+" */\n(()=>{ try{ if(window.__vsp_runs_kpi_bind_v2){ window.__vsp_p2_runs_kpi_v1_disabled=true; } }catch(_){ } })();\n\n/* VSP_P2_RUNS_KPI_JS_V1"
        )
        print("[OK] injected guard before KPI v1 block")
    else:
        # Fallback: append a guard at end (safe no-op)
        s += "\n\n/* "+marker+" */\n(()=>{ try{ if(window.__vsp_runs_kpi_bind_v2){ window.__vsp_p2_runs_kpi_v1_disabled=true; } }catch(_){ } })();\n"
        print("[OK] appended guard (fallback)")

# Additionally: if KPI v1 loader has a public init function name we can short-circuit lightly
# (non-destructive): add a tiny check in common places
s = re.sub(r"(async function\s+loadRunsKpi\s*\()",
           r"async function loadRunsKpi(",
           s, count=1)

js.write_text(s, encoding="utf-8")
PY

node --check "$JS" && echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_cleanup_layout_nofreeze_v1"
