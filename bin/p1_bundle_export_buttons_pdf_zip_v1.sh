#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_exportbtn_${TS}"
echo "[BACKUP] ${JS}.bak_exportbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_EXPORT_BTNS_PDF_ZIP_V1"

if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

needle = 'btns.appendChild(mk("Download JSON", "findings_unified.json"));'
idx = s.find(needle)
if idx < 0:
    raise SystemExit("[ERR] cannot find export buttons anchor: " + needle)

insert = r'''
/* %s
 * Add PDF/ZIP export via run_file_allow allowlist (no /api/vsp/export).
 * ZIP/PDF are best-effort: server may return ok:false if missing (commercial).
 */
try{
  btns.appendChild(mk("Download PDF", "reports/findings_unified.pdf"));
  // common alternates (open-first strategy; allowlist may 200-ok:false)
  const zipCandidates = [
    "reports/report_bundle.zip",
    "reports/findings_unified.zip",
    "report_bundle.zip",
    "report_artifacts.zip"
  ];
  const zipBtn = document.createElement("button");
  zipBtn.className = "vsp-btn vsp-btn-ghost";
  zipBtn.textContent = "Download ZIP";
  zipBtn.onclick = ()=> {
    const rid = (S && (S.rid || S.lastRid)) || "";
    const c0 = zipCandidates[0];
    window.open(`/api/vsp/run_file_allow?${qs({rid, path:c0})}`, "_blank");
  };
  btns.appendChild(zipBtn);
}catch(_){}
/* /%s */
''' % (MARK, MARK)

s = s[:idx+len(needle)] + insert + s[idx+len(needle):]

p.write_text(s, encoding="utf-8")
print("[OK] added PDF/ZIP export buttons marker:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check passed"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5, check export buttons."
