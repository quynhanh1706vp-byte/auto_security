#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "$F.bak_add_report_${TS}" && echo "[BACKUP] $F.bak_add_report_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

MARK="VSP_RUNS_ADD_REPORT_BTN_V1"
if MARK in s:
    print("[SKIP] already patched")
    raise SystemExit(0)

# 1) add button next to existing exports (best-effort string injection)
# Look for "Export PDF" label in HTML row buttons and append Report
s2 = s

# common pattern: buttons html string includes "Export PDF"
pat = re.compile(r'(Export\s*PDF</button>\s*)', re.I)
if pat.search(s2):
    s2 = pat.sub(r'''\1
          <button class="vsp-btn vsp-btn-ghost vsp-run-report-btn"
            data-rid="${rid}"
            title="Open CIO HTML report"
            style="padding:8px 10px; border-radius:10px; font-size:12px;">
            Report
          </button>
''', s2, count=1)

# 2) add event delegation handler
addon = r'''
/* VSP_RUNS_ADD_REPORT_BTN_V1: open CIO report (HTML route) */
(function(){
  'use strict';
  function normRid(x){
    if(!x) return "";
    return String(x).trim().replace(/^RID:\s*/i,'').replace(/^RUN_/i,'');
  }

  document.addEventListener("click", function(ev){
    const btn = ev.target && ev.target.closest ? ev.target.closest(".vsp-run-report-btn") : null;
    if(!btn) return;
    ev.preventDefault();
    const rid = normRid(btn.getAttribute("data-rid") || "");
    if(!rid){ alert("Missing RID"); return; }
    const url = "/vsp/report_cio_v1/" + encodeURIComponent(rid);
    window.open(url, "_blank", "noopener");
  }, true);
})();
'''
s2 = s2.rstrip() + "\n\n" + addon + "\n"

if s2 == s:
    print("[WARN] no obvious injection point found; appended handler only")

p.write_text(s2, encoding="utf-8")
print("[OK] patched runs tab: per-row Report button + handler")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_runs_add_report_per_row_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
