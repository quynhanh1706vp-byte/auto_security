#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"
export TS

fix_one () {
  local T="$1"
  [ -f "$T" ] || return 0
  cp -f "$T" "$T.bak_fixrid_${TS}" && echo "[BACKUP] $T.bak_fixrid_${TS}"

  python3 - <<'PY'
import os, re
from pathlib import Path

ts=os.environ.get("TS","1")
t=os.environ.get("T")  # optional, not used
PY
  python3 - <<PY
import os, re
from pathlib import Path

ts=os.environ.get("TS","1")
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) remove any broken script tag like /static/js/PYYYYmmdd_HHMMSS (no .js)
s=re.sub(r'<script[^>]+src="/static/js/P\\d{6,8}_\\d{6,}"[^>]*>\\s*</script>\\s*', '', s, flags=re.I)

# 2) force rid_state tag
rid_tag = '<script src="/static/js/vsp_rid_state_v1.js?v=' + ts + '"></script>'

if re.search(r'vsp_rid_state_v1\\.js', s):
    s=re.sub(r'<script[^>]+vsp_rid_state_v1\\.js[^>]*>\\s*</script>', rid_tag, s, flags=re.I)
else:
    s=re.sub(r'</body>', rid_tag + "\\n</body>", s, flags=re.I)

p.write_text(s, encoding="utf-8")
print("[OK] fixed rid_state script src in", p)
PY
}

fix_one "templates/vsp_4tabs_commercial_v1.html"
fix_one "templates/vsp_dashboard_2025.html"

echo "[DONE] Template fixed. Now restart 8910 + hard refresh Ctrl+Shift+R."
