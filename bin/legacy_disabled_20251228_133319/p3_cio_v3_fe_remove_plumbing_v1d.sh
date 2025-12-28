#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

patch_file(){
  local f="$1"
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "${f}.bak_cio_v3_fe_${TS}"
  echo "[BACKUP] ${f}.bak_cio_v3_fe_${TS}"

  python3 - "$f" <<'PY'
import re, sys
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

# 1) dashboard: gate via run_gate_v3 instead of run_file_allow path=run_gate_summary.json
s=re.sub(
  r'`/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=run_gate_summary\.json`',
  r'`/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid)}`',
  s
)

# 2) runs KPI compact: replace helper calls to run_file_allow for gate/findings
#   - common pattern: jget(`/api/vsp/run_file_allow?rid=...&path=...`)
#   We'll map:
#     gate -> /api/vsp/run_gate_v3?rid=...
#     findings -> /api/vsp/findings_v3?rid=...&limit=...&offset=...
def repl_run_file_allow(m):
    full=m.group(0)
    if "run_gate_summary" in full:
        # keep rid expression intact
        rid_expr=m.group("rid")
        return f"jget(`/api/vsp/run_gate_v3?rid=${{{rid_expr}}}`)"
    if "findings_unified" in full:
        rid_expr=m.group("rid")
        # preserve limit if exists in string, else default to limit=2000 for internal table
        if "&limit=" in full:
            return re.sub(r'/api/vsp/run_file_allow\?rid=\$\{[^}]+\}&path=\$\{encodeURIComponent\([^)]*\)\}&limit=\d+',
                          lambda _ : f"/api/vsp/findings_v3?rid=${{{rid_expr}}}&limit=500&offset=0",
                          full)
        return f"jget(`/api/vsp/findings_v3?rid=${{{rid_expr}}}&limit=500&offset=0`)"
    return full

s=re.sub(
  r'jget\(`\/api\/vsp\/run_file_allow\?rid=\$\{(?P<rid>encodeURIComponent\(rid\))\}&path=\$\{encodeURIComponent\([^)]*\)\}(?:&limit=\d+)?`\)',
  repl_run_file_allow,
  s
)

# 3) Replace open/download URLs that used run_file_allow to artifact_v3 kinds
# html/pdf/zip/tgz/csv/sarif
s=s.replace("/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(htmlPath)}&limit=200000",
            "/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=html&download=1")
s=s.replace("/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(pdfPath)}&limit=200000",
            "/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=pdf&download=1")

# zip/tgz were often computed as ridZipUrl -> patch generic pattern if present
s=re.sub(r'\/api\/vsp\/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*\)\}&limit=200000',
         "/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=zip&download=1",
         s)

# 4) Scrub obvious internal filename strings (UI text)
for leak in ["findings_unified.json","reports/findings_unified.json","run_gate_summary.json","reports/run_gate_summary.json"]:
    s=s.replace(leak,"")

if s==orig:
    print("[WARN] no change applied to", p)
else:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched", p)
PY
}

patch_file "static/js/vsp_dashboard_luxe_v1.js"
patch_file "static/js/vsp_runs_kpi_compact_v3.js"

echo
echo "[DONE] FE patched. Restart your browser hard-refresh (Ctrl+Shift+R) then re-check /runs."
