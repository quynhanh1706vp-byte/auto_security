#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

fix_one () {
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_fixrid_${TS}" && echo "[BACKUP] $T.bak_fixrid_${TS}"

  python3 - <<PY
from pathlib import Path
import re
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) Remove any broken script tag like /static/js/PYYYYmmdd_HHMMSS (no .js)
s=re.sub(r'<script[^>]+src="/static/js/P\\d{6,8}_\\d{6,}"[^>]*>\\s*</script>\\s*', '', s, flags=re.I)

# 2) Ensure a correct rid_state script tag exists (replace any existing rid_state tag)
rid_tag = f'<script src="/static/js/vsp_rid_state_v1.js?v={TS}"></script>'
if re.search(r'vsp_rid_state_v1\\.js', s):
    s=re.sub(r'<script[^>]+vsp_rid_state_v1\\.js[^>]*>\\s*</script>', rid_tag, s, flags=re.I)
else:
    # insert before closing body (safe)
    s=re.sub(r'</body>', rid_tag + "\\n</body>", s, flags=re.I)

p.write_text(s, encoding="utf-8")
print("[OK] fixed rid_state script src in", p)
PY
}

fix_one "templates/vsp_4tabs_commercial_v1.html"
fix_one "templates/vsp_dashboard_2025.html"

echo "[DONE] Template fixed. Restart 8910 + hard refresh Ctrl+Shift+R."
