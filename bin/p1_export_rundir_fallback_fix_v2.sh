#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

APP="vsp_demo_app.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rundirfix_v2_${TS}"
echo "[BACKUP] ${APP}.bak_rundirfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

start_pat = r'^(?P<ind>\s*)# --- VSP_P1_EXPORT_RUNDIR_FALLBACK_IN_HANDLER_V1 ---\s*$'
m = re.search(start_pat, s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find handler fallback marker V1 in file (maybe script v1 didn't inject?)")

ind = m.group("ind")
end_pat = r'^\s*# --- /VSP_P1_EXPORT_RUNDIR_FALLBACK_IN_HANDLER_V1.*$'
m2 = re.search(end_pat, s[m.end():], flags=re.M)
if not m2:
    raise SystemExit("[ERR] cannot find end marker for handler fallback V1")

block_start = m.start()
block_end = m.end() + m2.end()

new_block = (
f"{ind}# --- VSP_P1_EXPORT_RUNDIR_FALLBACK_IN_HANDLER_V1 ---\n"
f"{ind}# v2: request.args based (stable)\n"
f"{ind}try:\n"
f"{ind}    from flask import request as _vsp_req\n"
f"{ind}    __rid = (_vsp_req.args.get('rid') or _vsp_req.args.get('run_id') or _vsp_req.args.get('RID') or '').strip()\n"
f"{ind}    __rid_norm = ''\n"
f"{ind}    try:\n"
f"{ind}        import re as __re\n"
f"{ind}        mm = __re.search(r'(\\d{{8}}_\\d{{6}})', __rid)\n"
f"{ind}        __rid_norm = (mm.group(1) if mm else '').strip()\n"
f"{ind}    except Exception:\n"
f"{ind}        __rid_norm = ''\n"
f"{ind}    __cand = _vsp__resolve_run_dir_for_export(__rid, __rid_norm)\n"
f"{ind}    if __cand:\n"
f"{ind}        run_dir = __cand\n"
f"{ind}        ci_dir  = __cand\n"
f"{ind}        RUN_DIR = __cand\n"
f"{ind}except Exception:\n"
f"{ind}    pass\n"
f"{ind}# --- /VSP_P1_EXPORT_RUNDIR_FALLBACK_IN_HANDLER_V1 ---\n"
)

s2 = s[:block_start] + new_block + s[block_end:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] replaced handler fallback block with v2 (request.args based)")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== test export known RID (should stop 404 if resolver works) =="
RID="RUN_20251120_130310"
curl -sS -L -D /tmp/vsp_exp_hdr.txt -o /tmp/vsp_exp_body.bin \
  "$BASE/api/vsp/run_export_v3?rid=$RID&fmt=tgz" \
  -w "\nHTTP=%{http_code}\n"
echo "== Content-Disposition =="
grep -i '^Content-Disposition:' /tmp/vsp_exp_hdr.txt || true
echo "== Body head =="
head -c 220 /tmp/vsp_exp_body.bin; echo
