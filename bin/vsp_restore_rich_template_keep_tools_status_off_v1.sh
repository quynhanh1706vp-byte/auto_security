#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
TS="$(date +%Y%m%d_%H%M%S)"

# 1) pick best candidate template backup (avoid safe/freeze)
python3 - <<'PY'
import re, os, glob
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
cands = []
# collect many kinds of backups
patterns = [
  "templates/vsp_dashboard_2025.html.bak_*",
  "templates/vsp_dashboard_2025.html.*.bak_*",
  "templates/vsp_dashboard_2025.html.bak_*_*",
]
seen=set()
for pat in patterns:
  for p in glob.glob(pat):
    if p in seen: 
      continue
    seen.add(p)
    if any(x in p for x in ["bak_safe_", "bak_freeze_", "safe_", "freeze_"]):
      continue
    cands.append(Path(p))

def score(text:str)->int:
  keys = [
    "VersaSecure Platform", "SECURITY_BUNDLE",
    "Dashboard", "Runs & Reports", "Data Source", "Settings", "Rule Overrides",
    "OVERALL VERDICT", "Commercial Operational Policy",
    "TOTAL FINDINGS", "CRITICAL", "HIGH", "MEDIUM", "LOW",
    "severity", "findings",
    "vsp-tabs", "panel", "vsp-runs", "vsp-dashboard",
  ]
  s=0
  low=text.lower()
  for k in keys:
    if k.lower() in low: s += 5
  # script hints
  for k in ["vsp_tabs_hash_router", "vsp_runs_commercial", "vsp_dashboard_charts", "vsp_ui_commercial"]:
    if k in low: s += 12
  # root containers
  if re.search(r'id\s*=\s*["\']vsp-tabs', text, re.I): s += 20
  if re.search(r'id\s*=\s*["\']panel-dashboard', text, re.I): s += 20
  if re.search(r'id\s*=\s*["\']panel-runs', text, re.I): s += 20
  return s

best=None
best_score=-1
for p in cands:
  try:
    t = p.read_text(encoding="utf-8", errors="ignore")
  except Exception:
    continue
  sc = score(t)
  # prefer higher score, then newer mtime
  if sc > best_score or (sc == best_score and best and p.stat().st_mtime > best.stat().st_mtime):
    best = p
    best_score = sc

if not best:
  raise SystemExit("[ERR] cannot find a rich template backup (non safe/freeze). List templates/ manually.")

print(f"[PICK] {best} score={best_score}")
Path("out_ci").mkdir(exist_ok=True)
Path("out_ci/last_rich_tpl_pick.txt").write_text(str(best)+"\n", encoding="utf-8")
PY

PICK="$(cat out_ci/last_rich_tpl_pick.txt | head -n1)"
[ -f "$PICK" ] || { echo "[ERR] missing picked file: $PICK"; exit 2; }

# 2) backup current + restore picked
cp -f "$TPL" "$TPL.bak_before_rich_${TS}" && echo "[BACKUP] $TPL.bak_before_rich_${TS}"
cp -f "$PICK" "$TPL" && echo "[RESTORE] $TPL <= $PICK"

# 3) ALWAYS disable tools_status script tags in template (keep stability)
python3 - <<'PY'
import re
from pathlib import Path
p=Path("templates/vsp_dashboard_2025.html")
s=p.read_text(encoding="utf-8", errors="ignore")
s2=s
s2=re.sub(r'(?is)\s*<script[^>]+src="[^"]*vsp_tools_status[^"]*"[^>]*>\s*</script>\s*',
          "\n<!-- disabled: vsp_tools_status (stability) -->\n", s2)
s2=re.sub(r'(?is)\s*<script[^>]+src="[^"]*tools_status[^"]*"[^>]*>\s*</script>\s*',
          "\n<!-- disabled: tools_status (stability) -->\n", s2)
if s2!=s: print("[OK] removed tools_status script tags")
else: print("[WARN] no tools_status script tags found")
p.write_text(s2, encoding="utf-8")
PY

# 4) favicon (avoid noise)
mkdir -p static
[ -f static/favicon.ico ] || : > static/favicon.ico

# 5) restart 8910
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/ui_restart_check_8910_v1.sh

echo "[DONE] Rich template restored (tools_status still OFF). Now do Ctrl+Shift+R + Ctrl+0."
