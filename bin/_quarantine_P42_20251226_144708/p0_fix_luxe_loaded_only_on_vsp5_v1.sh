#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need curl; need head

TS="$(date +%Y%m%d_%H%M%S)"

# find likely templates
cand=()
for f in templates/*.html templates/**/*.html 2>/dev/null; do cand+=("$f"); done
if [ "${#cand[@]}" -eq 0 ]; then
  echo "[ERR] no templates found under templates/"; exit 2
fi

echo "== [1] Locate where vsp_dashboard_luxe_v1.js is included =="
hits="$(grep -RIn --line-number 'vsp_dashboard_luxe_v1\.js' templates | head -n 20 || true)"
echo "$hits"
[ -n "$hits" ] || { echo "[ERR] no luxe include found in templates"; exit 2; }

# pick the first hit file as primary (usually base/shell template)
T="$(echo "$hits" | head -n 1 | cut -d: -f1)"
[ -f "$T" ] || { echo "[ERR] cannot resolve template path"; exit 2; }

cp -f "$T" "${T}.bak_luxe_gate_${TS}"
echo "[BACKUP] ${T}.bak_luxe_gate_${TS}"

echo "== [2] Patch template to gate luxe JS to /vsp5 only =="

python3 - <<'PY'
from pathlib import Path
import re, time

t = Path(Path("templates") / Path("dummy")).parent  # keep relative
# actual path passed from bash via file read:
import os
T=os.environ.get("T_PATH")
p=Path(T)
s=p.read_text(encoding="utf-8", errors="replace")

# If already gated, skip
if re.search(r'if .*vsp5|/vsp5', s) and "vsp_dashboard_luxe_v1.js" in s:
    print("[OK] looks already gated; no change")
    raise SystemExit(0)

# Replace a direct script include with a Jinja gate.
# Works for patterns like: <script src="/static/js/vsp_dashboard_luxe_v1.js?v=..."></script>
pat = r'(<script[^>]+src="[^"]*vsp_dashboard_luxe_v1\.js[^"]*"[^>]*>\s*</script>)'
m=re.search(pat, s, flags=re.I)
if not m:
    print("[ERR] cannot find direct luxe script tag in template")
    raise SystemExit(3)

tag=m.group(1)
gate = (
    '{% if request.path == "/vsp5" %}\n'
    + tag +
    '\n{% endif %}'
)

s2 = s[:m.start()] + gate + s[m.end():]

p.write_text(s2, encoding="utf-8")
print("[OK] gated luxe JS include to /vsp5 in", p)
PY
