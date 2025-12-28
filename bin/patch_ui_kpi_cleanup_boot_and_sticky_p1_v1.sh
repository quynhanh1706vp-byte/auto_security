#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_kpi_cleanup_${TS}" && echo "[BACKUP] $F.bak_kpi_cleanup_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) remove BOOT + tick debug writes (keep DOM rid fallback)
s2=s

# remove BOOT line
s2 = re.sub(r'^\s*setText\(\s*"kpi-overall"\s*,\s*"BOOT"\s*\)\s*;\s*\n', '', s2, flags=re.M)
# replace boot-sub text
s2 = s2.replace('setText("kpi-overall-sub", "standalone alive (boot)");',
                'setText("kpi-overall-sub", "standalone alive");')
# remove tick-sub overwrite
s2 = re.sub(r'^\s*setText\(\s*"kpi-overall-sub"\s*,\s*"tick "\s*\+\s*now\.toISOString\(\)\s*\)\s*;\s*\n', '', s2, flags=re.M)

# 2) fix sticky-lock: do NOT mark stable blindly (only when value is real and not debug placeholders)
marker="VSP_KPI_STICKY_LOCK_P1_V1"
idx=s2.find(marker)
if idx < 0:
    raise SystemExit("[ERR] sticky lock marker not found (VSP_KPI_STICKY_LOCK_P1_V1)")

# replace markStable() function content inside sticky-lock block
pat = re.compile(r'function\s+markStable\s*\(\)\s*\{\s*[\s\S]*?\}\s*', re.M)
# search near marker window
win = s2[idx: idx+8000]
m = pat.search(win)
if not m:
    raise SystemExit("[ERR] cannot find markStable() near sticky lock marker")

new_mark = r'''function markStable(){
    for (var i=0;i<IDS.length;i++){
      var id = IDS[i];
      var e = el(id);
      try{
        if(!e) continue;
        if(!hasValue(e)) continue;
        var t = (e.textContent||"").trim();
        var u = t.toUpperCase();
        // don't lock placeholders/debug
        if(u==="N/A" || t==="…" || t==="—") continue;
        if(u==="BOOT") continue;
        if(t.startsWith("tick ")) continue;
        e.setAttribute("data-vsp-kpi-stable","1");
      }catch(_){}
    }
  }'''

win2 = win[:m.start()] + new_mark + win[m.end():]
s2 = s2[:idx] + win2 + s2[idx+8000:]

p.write_text(s2, encoding="utf-8")
print("[OK] cleaned BOOT/tick + fixed sticky lock markStable")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
