#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_trend_points_${TS}"
echo "[BACKUP] ${APP}.bak_trend_points_${TS}"

python3 - "$APP" <<'PY'
import re, sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# locate trend_v1 route block
m = re.search(r'(?s)(@app\.(?:route|get|post)\(\s*[\'"]/api/vsp/trend_v1[\'"].*?\)\s*\n\s*def\s+[a-zA-Z_]\w*\s*\([^)]*\)\s*:\s*\n)(.*?)(\n@app\.|\nif\s+__name__\s*==|\Z)', s)
if not m:
  print("[ERR] cannot locate /api/vsp/trend_v1 route")
  sys.exit(2)

head, body, tail = m.group(1), m.group(2), m.group(3)
# Find a 'return jsonify(...)' inside body
rm = re.search(r'(?m)^(?P<indent>\s*)return\s+jsonify\((?P<expr>.+?)\)\s*$', body)
if not rm:
  print("[ERR] trend_v1 has no 'return jsonify(...)' line to patch")
  sys.exit(2)

indent = rm.group("indent")
expr = rm.group("expr").strip()

# Build replacement
if expr.startswith("{"):
  repl = (
    f"{indent}_j = {expr}\n"
    f"{indent}# contract hardening: always provide points[]\n"
    f"{indent}try:\n"
    f"{indent}  _pts = _j.get('points', None)\n"
    f"{indent}except Exception:\n"
    f"{indent}  _pts = None\n"
    f"{indent}if not isinstance(_pts, list):\n"
    f"{indent}  _j['points'] = []\n"
    f"{indent}return jsonify(_j)"
  )
else:
  # expr is likely a variable name, wrap it
  repl = (
    f"{indent}_j = {expr}\n"
    f"{indent}# contract hardening: always provide points[]\n"
    f"{indent}if not isinstance(_j, dict):\n"
    f"{indent}  _j = {{'ok': True, 'points': []}}\n"
    f"{indent}else:\n"
    f"{indent}  _pts = _j.get('points', None)\n"
    f"{indent}  if not isinstance(_pts, list):\n"
    f"{indent}    _j['points'] = []\n"
    f"{indent}return jsonify(_j)"
  )

new_body = body[:rm.start()] + repl + body[rm.end():]
new_s = s[:m.start()] + head + new_body + tail + s[m.end():]

p.write_text(new_s, encoding="utf-8")
print("[OK] patched trend_v1 contract points[]")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] $SVC not active; restart manually if needed"
fi

echo "== verify =="
curl -fsS "$BASE/api/vsp/trend_v1" | python3 - <<'PY'
import json,sys
j=json.load(sys.stdin)
print("ok=", j.get("ok"), "has_points=", "points" in j, "points_type=", type(j.get("points")).__name__)
print("keys=", sorted(list(j.keys()))[:20])
PY
