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
cp -f "$APP" "${APP}.bak_move_run_files_${TS}"
echo "[BACKUP] ${APP}.bak_move_run_files_${TS}"

python3 - "$APP" <<'PY'
import re, sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

A="# --- VSP_P0_API_RUN_FILES_V1_WHITELIST ---"
B="# --- /VSP_P0_API_RUN_FILES_V1_WHITELIST ---"

if A not in s or B not in s:
    print("[ERR] run_files_v1 marker block not found")
    raise SystemExit(2)

# extract the whole block
block_pat = re.compile(re.escape(A) + r"[\s\S]*?" + re.escape(B) + r"\n?", re.M)
m = block_pat.search(s)
if not m:
    print("[ERR] cannot extract marker block")
    raise SystemExit(2)
block = m.group(0)

# remove it from current position
s2 = block_pat.sub("", s, count=1)

# find app = Flask(
m2 = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s2)
if not m2:
    # fallback: app=Flask(
    m2 = re.search(r'(?m)^\s*app\s*=\s*Flask\s*\(', s2)
if not m2:
    print("[ERR] cannot locate 'app = Flask(' to reinsert under it")
    raise SystemExit(2)

# insert right AFTER that line
line_end = s2.find("\n", m2.end())
if line_end < 0:
    line_end = m2.end()

insert_pos = line_end + 1

# Ensure decorator uses app.route (compat)
block = re.sub(r'@app\.get\(\s*[\'"]\/api\/vsp\/run_files_v1[\'"]\s*\)',
               '@app.route("/api/vsp/run_files_v1", methods=["GET"])',
               block, count=1)

# Ensure "import re" exists inside function (so regex filter works)
if "def api_vsp_run_files_v1" in block and "import re" not in block:
    block = block.replace("import os, time", "import os, time\n    import re", 1)

s3 = s2[:insert_pos] + block + "\n" + s2[insert_pos:]
p.write_text(s3, encoding="utf-8")
print("[OK] moved run_files_v1 block under app = Flask(...)")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true

echo "== status (short) =="
systemctl status "$SVC" --no-pager -l | head -n 40 || true

echo "== smoke =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 200 && echo || true
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/run_files_v1?rid=$RID" | head -c 300 && echo || true
