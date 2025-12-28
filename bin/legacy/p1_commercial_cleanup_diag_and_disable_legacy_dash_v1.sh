#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# 1) Remove force-visible HTML banner from templates
python3 - <<'PY'
from pathlib import Path
import re, time

ts=time.strftime("%Y%m%d_%H%M%S")
targets=[
  Path("templates/vsp_5tabs_enterprise_v2.html"),
  Path("templates/vsp_dashboard_2025.html"),
]
for p in targets:
  if not p.exists():
    print("[WARN] missing:", p); continue
  s=p.read_text(encoding="utf-8", errors="replace")
  bak=p.with_name(p.name+f".bak_cleanup_diag_{ts}")
  bak.write_text(s, encoding="utf-8")

  # remove injected block (style + banner div)
  s2 = re.sub(r'\n?<!--\s*VSP_FORCE_VISIBLE_V1\s*-->.*?VSP HTML LOADED \(force-visible v1\).*?</div>\n?',
              '\n', s, flags=re.S|re.I)
  # also remove the style id if left behind
  s2 = re.sub(r'\n?<style[^>]*id="VSP_FORCE_VISIBLE_V1"[^>]*>.*?</style>\n?', '\n', s2, flags=re.S|re.I)

  p.write_text(s2, encoding="utf-8")
  print("[OK] cleaned template:", p, "backup:", bak)
PY

# 2) Remove topbar diag append
TB="static/js/vsp_topbar_commercial_v1.js"
if [ -f "$TB" ]; then
  cp -f "$TB" "${TB}.bak_cleanup_diag_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_topbar_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
s2 = re.sub(r'\n?/\*\s*VSP_TOPBAR_FORCE_VISIBLE_V1\s*\*/.*?\)\(\);\s*\n?',
            '\n', s, flags=re.S|re.I)
p.write_text(s2, encoding="utf-8")
print("[OK] cleaned topbar diag:", p)
PY
fi

# 3) Remove KPI v3 diag banner + boot log line (keep logic)
KPI="static/js/vsp_dashboard_kpi_toolstrip_v3.js"
if [ -f "$KPI" ]; then
  cp -f "$KPI" "${KPI}.bak_cleanup_diag_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_kpi_toolstrip_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

# remove injected console boot line
s = re.sub(r'\n\s*try\{\s*console\.info\("\[VSP\]\[KPI_V3\]\s*boot".*?\);\s*\}\s*catch\(_\)\{\s*\}\s*\n',
           '\n', s, flags=re.S)

# remove appended JS banner block
s = re.sub(r'\n?/\*\s*VSP_KPI_V3_DIAG_BANNER_V1\s*\*/.*?\)\(\);\s*\n?',
           '\n', s, flags=re.S|re.I)

p.write_text(s, encoding="utf-8")
print("[OK] cleaned KPI diag:", p)
PY
fi

# 4) Disable legacy DASH scripts on /vsp5 by signature (STABLE_V1 / rid_latest / <URL>)
python3 - <<'PY'
from pathlib import Path
import re, time

ts=time.strftime("%Y%m%d_%H%M%S")
root=Path("static/js")
if not root.exists():
  print("[WARN] no static/js"); raise SystemExit(0)

sig = re.compile(r'(DASH\]\[STABLE_V1|rid_latest|Fetch finished loading:\s*GET\s*"<URL>"|\/vsp5:32)', re.I)
patched=[]
for p in root.rglob("*.js"):
  if p.name.endswith((".min.js",)): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  if not sig.search(s):
    continue
  if "VSP_DISABLE_LEGACY_DASH_ON_VSP5_V1" in s:
    continue
  bak=p.with_name(p.name+f".bak_disable_dash_{ts}")
  bak.write_text(s, encoding="utf-8")

  # inject guard at top of file (safe even if not IIFE)
  guard = '/* VSP_DISABLE_LEGACY_DASH_ON_VSP5_V1 */\n' \
          'try{ if (String(location.pathname||"").includes("/vsp5")) { /* no legacy dash on vsp5 */ } }catch(_){ }\n'
  # stronger: if code is an IIFE, early-return there
  s2 = re.sub(r'\(\(\)\s*=>\s*\{\s*\n',
              r'(() => {\n  /* VSP_DISABLE_LEGACY_DASH_ON_VSP5_V1 */\n  try{ if (String(location.pathname||"").includes("/vsp5")) return; }catch(_){ }\n',
              s, count=1)
  if s2 == s:
    s2 = guard + s
  p.write_text(s2, encoding="utf-8")
  patched.append(str(p))

print(f"[OK] disabled legacy dash candidates: {len(patched)}")
for x in patched[:20]:
  print(" -", x)
PY

echo "[DONE] cleanup + disable legacy dash applied."
