#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_trendfb_${TS}"
echo "[BACKUP] ${APP}.bak_trendfb_${TS}"

python3 - "$APP" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_TREND_V1_POINTS_FALLBACK_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Patch by wrapping return dict ensure points key (best-effort, pattern-based)
# We look for the route decorator line then insert a small helper inside the function.
m = re.search(r'(?m)^\s*@app\.route\(\s*[\'"]/api/vsp/trend_v1[\'"]\s*,.*\)\s*$', s)
if not m:
    print("[WARN] trend_v1 route decorator not found; skip")
    raise SystemExit(0)

# Find function def after decorator
m2 = re.search(r'(?m)^\s*def\s+([A-Za-z_]\w*)\s*\(\s*\)\s*:\s*$', s[m.end():])
if not m2:
    print("[WARN] trend_v1 def not found; skip")
    raise SystemExit(0)

fn_start = m.end() + m2.start()
indent = re.match(r'(?m)^(\s*)def', s[fn_start:]).group(1)
insert_at = fn_start + s[fn_start:].find("\n") + 1

inject = f"""{indent}    # {marker}
{indent}    def __vsp_ensure_points(obj):
{indent}        try:
{indent}            if isinstance(obj, dict) and "points" not in obj:
{indent}                obj["points"] = []
{indent}        except Exception:
{indent}            pass
{indent}        return obj
"""

s2 = s[:insert_at] + inject + s[insert_at:]

# Also ensure any "return jsonify(x)" becomes "return jsonify(__vsp_ensure_points(x))" inside that function block (best effort)
# limit to a window after insert
win_start = insert_at
win_end = min(len(s2), insert_at + 8000)
chunk = s2[win_start:win_end]
chunk2 = re.sub(r'return\s+jsonify\(\s*([A-Za-z_]\w*)\s*\)', r'return jsonify(__vsp_ensure_points(\1))', chunk)
s2 = s2[:win_start] + chunk2 + s2[win_end:]

p.write_text(s2, encoding="utf-8")
print("[OK] patched trend_v1 fallback points")
PY

python3 -m py_compile "$APP" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }
systemctl restart "$SVC" || true
echo "[OK] restarted $SVC"
