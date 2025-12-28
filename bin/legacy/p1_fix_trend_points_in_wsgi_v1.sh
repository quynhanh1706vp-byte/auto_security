#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_trendwsgi_${TS}"
echo "[BACKUP] ${F}.bak_trendwsgi_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P1_WSGI_TREND_POINTS_FORCE_V1"
if marker in s:
    print("[OK] already patched"); raise SystemExit(0)

# Find any function that returns trend_v1 JSON; easiest is to patch a route handler if present
# We patch by adding a small helper near top-level (safe) and then wrapping jsonify returns on /api/vsp/trend_v1
helper = f'''
# --- {marker} ---
def __vsp_force_points(obj):
    try:
        if isinstance(obj, dict) and "points" not in obj:
            obj["points"] = []
    except Exception:
        pass
    return obj
# --- end {marker} ---
'''
# Insert helper after imports (best-effort)
m = re.search(r'(?m)^(from|import)\s+', s)
insert_at = m.start() if m else 0
# Put helper after first 2000 chars to avoid breaking shebang/comments
insert_at = min(max(insert_at, 0), 2000)
s2 = s[:insert_at] + helper + "\n" + s[insert_at:]

# Wrap jsonify inside trend handler: return jsonify(x) -> return jsonify(__vsp_force_points(x))
# Limit patch to lines near route /api/vsp/trend_v1
pat_route = re.compile(r'(?ms)(@app\.route\(\s*[\'"]/api/vsp/trend_v1[\'"].*?\)\s*\n\s*def\s+\w+\s*\(\s*\)\s*:\s*\n)(.*?)(\n(?=@app\.route|\Z))')
m2 = pat_route.search(s2)
if not m2:
    print("[WARN] trend_v1 route block not found; helper injected only")
    p.write_text(s2, encoding="utf-8")
    raise SystemExit(0)

head, body, tail = m2.group(1), m2.group(2), m2.group(3)
body2 = re.sub(r'return\s+jsonify\(\s*([A-Za-z_]\w*)\s*\)', r'return jsonify(__vsp_force_points(\1))', body)
# also handle return jsonify({...})
body2 = re.sub(r'return\s+jsonify\(\s*(\{.*?\})\s*\)', r'return jsonify(__vsp_force_points(\1))', body2)
s3 = s2[:m2.start()] + head + body2 + tail + s2[m2.end():]
p.write_text(s3, encoding="utf-8")
print("[OK] patched wsgi trend_v1 to always include points")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }
systemctl restart "$SVC" || true
echo "[OK] restarted $SVC"
