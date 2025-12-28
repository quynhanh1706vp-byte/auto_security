#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

patch_file(){
  local f="$1"
  [ -f "$f" ] || { echo "[WARN] missing $f (skip)"; return 0; }
  cp -f "$f" "${f}.bak_cosmetic_${TS}"
  echo "[OK] backup: ${f}.bak_cosmetic_${TS}"
}

patch_file static/js/vsp_pin_dataset_badge_v1.js
patch_file static/js/vsp_cio_build_stamp_v1.js

python3 - <<'PY'
from pathlib import Path

def rep(path, pairs):
    p=Path(path)
    if not p.is_file(): 
        return
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    for a,b in pairs:
        s=s.replace(a,b)
    if s!=orig:
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", path)
    else:
        print("[OK] no change", path)

rep("static/js/vsp_pin_dataset_badge_v1.js", [
  ('DATA SOURCE: (ERR)', 'DATA SOURCE: —'),
  ('DATA SOURCE:(ERR)', 'DATA SOURCE: —'),
])

rep("static/js/vsp_cio_build_stamp_v1.js", [
  (' • Build: (api fail)', ' • Build: —'),
  ('Build: (api fail)', 'Build: —'),
])
PY

echo "[DONE] Hard refresh browser: Ctrl+Shift+R"
