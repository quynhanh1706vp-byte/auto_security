#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

# 0) restore from latest known-good backup (prefer bak_kpi_cleanup_*)
pick_latest() { ls -1t "$@" 2>/dev/null | head -n1 || true; }

B="$(pick_latest "${F}.bak_kpi_cleanup_"* )"
[ -z "${B:-}" ] && B="$(pick_latest "${F}.bak_kpi_dbg_"* )"
[ -z "${B:-}" ] && B="$(pick_latest "${F}.bak_kpi_sticky_"* )"
[ -z "${B:-}" ] && B="$(pick_latest "${F}.bak_rid_fallback_"* )"

if [ -n "${B:-}" ]; then
  cp -f "$B" "$F"
  echo "[RESTORE] $B -> $F"
else
  echo "[WARN] no backup found; will patch in-place"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_cleanup_v2_${TS}" && echo "[BACKUP] $F.bak_cleanup_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

# 1) remove BOOT try/catch block (keep DOM rid fallback)
# remove the specific debug try/catch block if present
s = re.sub(
  r'(?is)\n\s*//\s*===\s*VSP_KPI_STANDALONE_DEBUG_DOMRID_P1_V2\s*===\s*\n\s*try\s*\{\s*[^}]*?setText\(\s*"kpi-overall"\s*,\s*"BOOT"\s*\)\s*;[\s\S]*?\}\s*catch\s*\(\s*_\s*\)\s*\{\s*\}\s*',
  '\n  // === VSP_KPI_STANDALONE_DEBUG_DOMRID_P1_V2 ===\n',
  s,
  count=1
)

# also remove any remaining BOOT setText lines (just in case)
s = re.sub(r'(?im)^\s*setText\(\s*"kpi-overall"\s*,\s*"BOOT"\s*\)\s*;\s*$', '', s)

# remove tick overwrite block inside tick() if exists
s = re.sub(
  r'(?is)\n\s*try\s*\{\s*\n\s*var\s+now\s*=\s*new\s+Date\(\)\s*;\s*\n\s*setText\(\s*"kpi-overall-sub"\s*,\s*"tick "\s*\+\s*now\.toISOString\(\)\s*\)\s*;\s*\n\s*\}\s*catch\s*\(\s*_\s*\)\s*\{\s*\}\s*',
  '\n',
  s
)

# normalize any "standalone alive (boot)" -> "standalone alive"
s = s.replace('standalone alive (boot)', 'standalone alive')

# 2) Fix sticky-lock markStable safely by brace-matching (no regex truncation)
marker = "VSP_KPI_STICKY_LOCK_P1_V1"
i = s.find(marker)
if i < 0:
  raise SystemExit("[ERR] cannot find sticky marker VSP_KPI_STICKY_LOCK_P1_V1")

win_start = max(0, i-200)
win_end = min(len(s), i+20000)
win = s[win_start:win_end]

key = "function markStable"
j = win.find(key)
if j < 0:
  raise SystemExit("[ERR] cannot find function markStable() near sticky marker")

abs_j = win_start + j
# find opening brace
k = s.find("{", abs_j)
if k < 0:
  raise SystemExit("[ERR] cannot find '{' for markStable")

depth = 0
end = None
for pos in range(k, len(s)):
  ch = s[pos]
  if ch == "{":
    depth += 1
  elif ch == "}":
    depth -= 1
    if depth == 0:
      end = pos
      break
if end is None:
  raise SystemExit("[ERR] cannot brace-match markStable() block")

new_mark = """function markStable(){
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
        if(t.indexOf("tick ")===0) continue;
        e.setAttribute("data-vsp-kpi-stable","1");
      }catch(_){}
    }
  }"""

# replace whole function markStable(){...}
func_start = abs_j
func_end = end+1
s = s[:func_start] + new_mark + s[func_end:]

p.write_text(s, encoding="utf-8")
print("[OK] cleaned BOOT/tick + brace-safe fixed markStable")
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"
echo "[NOTE] restart gunicorn + hard refresh Ctrl+Shift+R"
