#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p62hotfix_${TS}"
echo "[OK] backup ${APP}.bak_p62hotfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, datetime, sys

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

changed = 0
for i in range(1, len(lines)):
    cur = lines[i]
    prev = lines[i-1]
    # match: line is just ", 200"
    if re.match(r'^\s*,\s*200\s*$', cur):
        # only merge if previous line looks like "return jsonify(...)" (common in your handler)
        if ("return" in prev) and ("jsonify" in prev) and (prev.rstrip().endswith(")")) and (", 200" not in prev):
            lines[i-1] = prev.rstrip("\n").rstrip() + ", 200\n"
            lines[i] = ""  # remove stray line
            changed += 1

# also handle pattern: "return jsonify(...)\n    , 200" (keep safe)
s = "".join(lines)
s2 = re.sub(r'(return\s+jsonify\([^\n]*\))\s*\n(\s*),\s*200\b', r'\1, 200', s)
if s2 != s:
    changed += 1
    s = s2

p.write_text(s, encoding="utf-8")
print(f"[OK] fixed stray ', 200' occurrences: {changed}")
PY

echo "== py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== restart service =="
sudo systemctl restart "$SVC"

echo "== wait /vsp5 up =="
ok=0
for i in $(seq 1 25); do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 2 "$BASE/vsp5" || true)"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 0.4
done
[ "$ok" = "1" ] || { echo "[ERR] UI not up"; exit 2; }
echo "[OK] /vsp5 200"
