#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

python3 - <<'PY'
from pathlib import Path
import datetime

p = Path("wsgi_vsp_p910h.py")
s = p.read_text(encoding="utf-8", errors="replace")

bk = Path(f"wsgi_vsp_p910h.py.bak_p910h4_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
bk.write_text(s, encoding="utf-8")
print("[OK] backup =>", bk)

if "P910H4_RUN_STATUS_GUARD" in s:
    print("[OK] guard already present")
    raise SystemExit(0)

# find ops_latest block to insert BEFORE it
needle = 'if path.rstrip("/") == "/api/vsp/ops_latest_v1":'
pos = s.find(needle)
if pos < 0:
    needle = 'if path == "/api/vsp/ops_latest_v1":'
    pos = s.find(needle)
if pos < 0:
    raise SystemExit("[ERR] cannot find ops_latest if-block in wrapper")

# get line indent where ops_latest begins
line_start = s.rfind("\n", 0, pos) + 1
indent = ""
while line_start + len(indent) < len(s) and s[line_start + len(indent)] in (" ", "\t"):
    indent += s[line_start + len(indent)]

guard = (
    f"{indent}# P910H4_RUN_STATUS_GUARD (stop 400/404 spam for missing/garbage rid)\n"
    f"{indent}if path.rstrip('/') == '/api/vsp/run_status_v1':\n"
    f"{indent}    try:\n"
    f"{indent}        from urllib.parse import parse_qs\n"
    f"{indent}        q = parse_qs(qs or '', keep_blank_values=True)\n"
    f"{indent}        rid = ''\n"
    f"{indent}        if 'rid' in q and q['rid']:\n"
    f"{indent}            rid = (q['rid'][0] or '').strip()\n"
    f"{indent}        rl = rid.lower().strip()\n"
    f"{indent}        if (not rid) or (rl in ('undefined','null','none','nan')) or rl.startswith('undefined'):\n"
    f"{indent}            return _resp({{'ok': False, 'rid': None, 'state': 'NO_RID'}}, 200)(environ, start_response)\n"
    f"{indent}    except Exception:\n"
    f"{indent}        return _resp({{'ok': False, 'rid': None, 'state': 'NO_RID'}}, 200)(environ, start_response)\n"
    f"\n"
)

s2 = s[:line_start] + guard + s[line_start:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted guard before ops_latest block")
PY

python3 -m py_compile wsgi_vsp_p910h.py
echo "[OK] wrapper py_compile OK"

sudo systemctl restart "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== verify run_status NO rid => 200 =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1" | head -n 5

echo "== verify run_status rid=undefined => 200 =="
curl -sS -D- -o /dev/null "$BASE/api/vsp/run_status_v1?rid=undefined" | head -n 5

echo "== verify ops_latest still OK =="
curl -sS -o /tmp/ops.json "$BASE/api/vsp/ops_latest_v1"
wc -c /tmp/ops.json

echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
