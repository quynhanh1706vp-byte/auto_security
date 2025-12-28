#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_clean_keep_lazyfind_${TS}"
echo "[BACKUP] ${JS}.bak_clean_keep_lazyfind_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove injected blocks EXCEPT lazy-findings (so dashboard stays light)
remove_markers = [
  "VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V1",
  "VSP_P1_RUN_GATE_SUMMARY_OK_NORMALIZE_V2",
  "VSP_P1_XHR_RUNGATE_NORMALIZE_V1",
  "VSP_P1_REWRITE_RUN_GATE_TO_SUMMARY_V1",
  "VSP_P1_AFTERREQ_OKWRAP_RUNFILEALLOW_V1",
  "VSP_P1_AFTER_REQUEST_OKWRAP_RUNGATE_SUMMARY_V2",
  "VSP_P1_AFTERREQ_OKWRAP_RUNFILEALLOW_V1",  # duplicate guard
  "VSP_P1_REWRITE_RUN_GATE_TO_SUMMARY_V1",
  "VSP_P1_XHR_RUNGATE_NORMALIZE_V1",
]

n_total = 0
for m in remove_markers:
    pat = re.compile(
        r"/\*\s*=+\s*"+re.escape(m)+r"\s*=+.*?\*/\s*(?:.|\n)*?/\*\s*=+\s*/"+re.escape(m)+r"\s*=+.*?\*/\s*",
        re.MULTILINE
    )
    s2, n = pat.subn("", s)
    if n:
        n_total += n
        s = s2

p.write_text(s, encoding="utf-8")
print("[OK] removed blocks =", n_total)
PY

command -v node >/dev/null 2>&1 && node --check "$JS" && echo "[OK] node --check passed" || true
systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] cleaned bundle (kept lazy-findings). Now Ctrl+Shift+R /vsp5"
