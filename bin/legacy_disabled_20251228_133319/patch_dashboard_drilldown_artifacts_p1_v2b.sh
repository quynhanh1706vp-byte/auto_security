#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_dashboard_enhance_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_drill_art_fix_${TS}" && echo "[BACKUP] $F.bak_drill_art_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_dashboard_enhance_v1.js")
s=p.read_text(encoding="utf-8", errors="ignore")

bad = 'q.querySelector("div[style*=\'display:flex\']")?.innerHTML = quick;'
if bad not in s:
    print("[WARN] target line not found; nothing to patch")
else:
    s = s.replace(
        bad,
        'const _box = q.querySelector("div[style*=\\"display:flex\\"]");\n      if(_box) _box.innerHTML = quick;'
    )
    p.write_text(s, encoding="utf-8")
    print("[OK] replaced invalid optional-chaining assignment")
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_drilldown_artifacts_p1_v2b"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
