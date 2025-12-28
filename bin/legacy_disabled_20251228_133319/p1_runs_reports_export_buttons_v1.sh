#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

if grep -q "VSP_P1_RUNS_EXPORT_BTNS_V1" "$TPL"; then
  echo "[OK] already patched: $TPL"
  exit 0
fi

cp -f "$TPL" "${TPL}.bak_exportbtn_${TS}"
echo "[BACKUP] ${TPL}.bak_exportbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("templates/vsp_runs_reports_v1.html")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) inject small helper JS (if page already has JS, append near end before </body>)
js = r"""
<!-- VSP_P1_RUNS_EXPORT_BTNS_V1 -->
<script>
function vspExportCsv(rid){
  if(!rid) return;
  window.open('/api/vsp/export_csv?rid=' + encodeURIComponent(rid), '_blank');
}
function vspExportTgzReports(rid){
  if(!rid) return;
  window.open('/api/vsp/export_tgz?rid=' + encodeURIComponent(rid) + '&scope=reports', '_blank');
}
function vspHasBadge(ok, label){
  if(!label) label = 'N/A';
  var cls = ok ? 'vsp-has-ok' : 'vsp-has-no';
  return '<span class="vsp-has '+cls+'">'+label+'</span>';
}
</script>
<style>
/* tiny badges */
.vsp-has{ display:inline-block; padding:2px 8px; border-radius:999px; font-size:12px; margin-right:6px; }
.vsp-has-ok{ background:rgba(34,197,94,.15); color:#22c55e; border:1px solid rgba(34,197,94,.35);}
.vsp-has-no{ background:rgba(148,163,184,.10); color:#94a3b8; border:1px solid rgba(148,163,184,.25);}
.vsp-btn{ border:1px solid rgba(148,163,184,.25); padding:6px 10px; border-radius:10px; font-size:12px; cursor:pointer; background:rgba(15,23,42,.55); color:#e2e8f0; }
.vsp-btn:hover{ border-color:rgba(226,232,240,.35); }
</style>
<!-- /VSP_P1_RUNS_EXPORT_BTNS_V1 -->
"""

if "</body>" in s:
    s = s.replace("</body>", js + "\n</body>", 1)
else:
    s += "\n" + js

# 2) Add columns header: Actions + Artifacts (best effort)
# Try locate a table header row
s = re.sub(r'(<tr[^>]*>\s*)(<th[^>]*>.*?</th>\s*)',
           r'\1\2<th style="text-align:left;">Artifacts</th><th style="text-align:left;">Export</th>',
           s, count=1, flags=re.S)

# 3) In each row, add badges + buttons.
# We look for the first </tr> after a run row template and inject cells before it.
# Common patterns: row html includes rid in data-rid or similar. We'll be conservative:
marker = "VSP_P1_RUNS_EXPORT_BTNS_V1_ROW"
if marker not in s:
    # Insert using a heuristic: find first occurrence of "</tr>" after "run_id" text.
    # If template uses JS to build rows, we can't patch reliably; but most of your runs page is server-side rendered.
    parts = s.split("</tr>", 1)
    if len(parts) == 2:
        head, tail = parts
        inject = r"""
<td><!-- """+marker+r""" -->
  <span class="vsp-has vsp-has-no">has.csv?</span>
  <span class="vsp-has vsp-has-no">has.json?</span>
  <span class="vsp-has vsp-has-no">has.summary?</span>
</td>
<td>
  <button class="vsp-btn" onclick="vspExportCsv((this.closest('tr')?.dataset?.rid)||'')">Export CSV</button>
  <button class="vsp-btn" onclick="vspExportTgzReports((this.closest('tr')?.dataset?.rid)||'')">Export TGZ</button>
</td>
"""
        s = head + inject + "</tr>" + tail

# 4) Make sure <tr> has data-rid if not present: patch first rid render to set dataset.
# If there is a placeholder like data-rid="{{ rid }}" you already have; otherwise we add to first <tr ...>
s = re.sub(r'<tr(?![^>]*data-rid)([^>]*)>',
           r'<tr data-rid="{{ item.run_id if item is defined else rid }}" \1>',
           s, count=1)

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

echo "[OK] patched $TPL"
echo "[HINT] restart UI then open /runs"
