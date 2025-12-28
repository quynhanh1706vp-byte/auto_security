#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

FILES=(
  "static/js/vsp_runs_tab_8tools_v1.js"
  "static/js/vsp_ui_4tabs_commercial_v1.js"
)

TS="$(date +%Y%m%d_%H%M%S)"
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  cp -f "$f" "$f.bak_silent_export_${TS}"
  echo "[BACKUP] $f.bak_silent_export_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import re

def patch_runs8(s: str) -> str:
    # replace headOk() body if exists
    s2 = s
    s2 = re.sub(
        r'async function headOk\s*\(\s*url\s*\)\s*\{[\s\S]*?\n\}',
        '''async function headOk(url){
  try{
    const r = await fetch(url, {method:"HEAD", cache:"no-store"});
    // commercial: treat not-ready as false, no console noise
    const avail = (r.headers.get("x-vsp-export-available")||"").trim();
    if (r.status === 200 && avail === "0") return false;
    return r.ok;
  }catch(_e){
    return false;
  }
}''',
        s2,
        count=1
    )
    # remove noisy console lines like: console.warn("HEAD", ...)
    s2 = re.sub(r'console\.(warn|error|log)\([^)]*HEAD[^)]*\);\s*', '', s2)
    return s2

def patch_ui4(s: str) -> str:
    # silence _vsp_try_head-like logs
    s2 = s
    s2 = re.sub(r'console\.(warn|error|log)\([^)]*run_export_v3[^)]*\);\s*', '', s2)
    # if there is a helper doing HEAD, make it non-noisy by removing explicit throws
    s2 = re.sub(r'throw new Error\([^)]*HEAD[^)]*\);\s*', 'return {ok:false,status:0};', s2)
    return s2

# apply
p1 = Path("static/js/vsp_runs_tab_8tools_v1.js")
if p1.exists():
    t = p1.read_text(encoding="utf-8", errors="ignore")
    t2 = patch_runs8(t)
    if t2 != t:
        p1.write_text(t2, encoding="utf-8")
        print("[OK] patched", p1)

p2 = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
if p2.exists():
    t = p2.read_text(encoding="utf-8", errors="ignore")
    t2 = patch_ui4(t)
    if t2 != t:
        p2.write_text(t2, encoding="utf-8")
        print("[OK] patched", p2)
PY

echo "[DONE] restart 8910 + hard refresh (Ctrl+Shift+R)"
