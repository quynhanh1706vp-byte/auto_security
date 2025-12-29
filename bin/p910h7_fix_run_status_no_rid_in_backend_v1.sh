#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
APP="vsp_demo_app.py"

echo "== [P910H7] backup =="
cp -f "$APP" "${APP}.bak_p910h7_${TS}"
echo "[OK] backup => ${APP}.bak_p910h7_${TS}"

echo "== [P910H7] patch run_status_v1 => 200 NO_RID =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "P910H7_RUN_STATUS_NO_RID_GUARD" in s:
    print("[OK] already patched")
    raise SystemExit(0)

# find decorator for run_status_v1
m = re.search(r'@app\.(get|route)\(\s*[\'"]\/api\/vsp\/run_status_v1[\'"]', s)
if not m:
    raise SystemExit("[ERR] cannot find /api/vsp/run_status_v1 decorator in vsp_demo_app.py")

# find function def after decorator
after = s[m.start():]
m2 = re.search(r'\n\s*def\s+([A-Za-z_]\w*)\s*\(', after)
if not m2:
    raise SystemExit("[ERR] cannot find def after run_status_v1 decorator")

func_name = m2.group(1)
func_pos = m.start() + m2.start() + 1  # points to "def ..."
# locate the def line end
def_line_end = s.find("\n", func_pos)
if def_line_end < 0:
    raise SystemExit("[ERR] malformed def line")

# compute indent inside function (def indent + 4 spaces)
def_line = s[func_pos:def_line_end]
def_indent = re.match(r'\s*', def_line).group(0)
indent = def_indent + "    "

guard = (
f"{indent}# P910H7_RUN_STATUS_NO_RID_GUARD\n"
f"{indent}rid = (request.args.get('rid','') or '').strip()\n"
f"{indent}rl = rid.lower()\n"
f"{indent}if (not rid) or (rl in ('undefined','null','none','nan')) or rl.startswith('undefined'):\n"
f"{indent}    resp = jsonify({{'ok': False, 'rid': None, 'state': 'NO_RID'}})\n"
f"{indent}    resp.headers['X-VSP-RUNSTATUS-GUARD'] = 'P910H7'\n"
f"{indent}    return resp, 200\n"
"\n"
)

# insert AFTER optional docstring if exists
body_start = def_line_end + 1
# skip possible blank lines
i = body_start
while i < len(s) and s[i] in "\r\n":
    i += 1

# if docstring triple-quote at first statement
if s[i:i+3] in ("'''",'"""'):
    q = s[i:i+3]
    j = s.find(q, i+3)
    if j != -1:
        j2 = s.find(q, j+3)
        if j2 != -1:
            insert_at = j2 + 3
            nl = s.find("\n", insert_at)
            if nl != -1:
                insert_at = nl + 1
            else:
                insert_at = insert_at
        else:
            insert_at = body_start
    else:
        insert_at = body_start
else:
    insert_at = body_start

s2 = s[:insert_at] + guard + s[insert_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched function:", func_name)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [P910H7] restart =="
sudo systemctl restart "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== [P910H7] verify (must be 200 + header) =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1" | awk 'NR<=30'
echo
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1?rid=undefined" | awk 'NR<=30'

echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
