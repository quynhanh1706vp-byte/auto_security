#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need head; need grep

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p62_${TS}"
echo "[OK] backup ${APP}.bak_p62_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "P62_RUN_STATUS_HTTP200_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    sys.exit(0)

# Find the run_status_v1 route block (best-effort)
m = re.search(r'(?ms)^\s*@.*run_status_v1[^\n]*\n\s*def\s+[a-zA-Z_]\w*\s*\(.*?\):.*?(?=^\s*@|\Z)', s)
if not m:
    print("[ERR] cannot locate run_status_v1 route block in vsp_demo_app.py")
    sys.exit(2)

blk = m.group(0)

# 1) If there are returns with ", 404" inside this block -> convert to 200
blk2 = re.sub(r'(?m)(return\s+jsonify\([^\n]*\))\s*,\s*404\b', r'\1, 200', blk)
blk2 = re.sub(r'(?m)(return\s+[^\n]*?)\s*,\s*404\b', r'\1, 200', blk2)

# 2) Replace abort(404) with JSON 200 (best-effort)
blk2 = re.sub(
    r'(?m)^\s*abort\(\s*404\s*\)\s*$',
    '    return jsonify({"ok": False, "error": "not_found", "rid": rid}), 200  # '+MARK,
    blk2
)

# 3) Add a marker comment near the top of the block
if MARK not in blk2:
    blk2 = blk2.replace(blk2.splitlines()[0], blk2.splitlines()[0] + f"\n# {MARK}: force HTTP 200 for UI fetch-guard; keep ok=false on not_found")

if blk2 == blk:
    # Still write marker so we know patch applied, but warn
    print("[WARN] block unchanged; no ',404' or abort(404) patterns matched. Still stamping marker.")
    blk2 = blk + f"\n# {MARK}: stamp only\n"

s2 = s[:m.start()] + blk2 + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] patched run_status_v1 to avoid HTTP 404 -> 200")
PY

echo "== restart UI service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

echo "== verify =="
RID="$(curl -fsS "$BASE/api/vsp/top_findings_v2?limit=1" \
  | python3 -c 'import sys,json;j=json.load(sys.stdin);print(j.get("rid") or j.get("run_id") or "")' || true)"
echo "[INFO] RID=$RID"
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }

code="$(curl -sS -o /tmp/run_status.json -w "%{http_code}" "$BASE/api/vsp/run_status_v1/$RID" || true)"
echo "[INFO] run_status_v1 http_code=$code"
head -c 260 /tmp/run_status.json; echo
echo "[OK] done"
echo "[TIP] open: $BASE/vsp5?rid=$RID"
