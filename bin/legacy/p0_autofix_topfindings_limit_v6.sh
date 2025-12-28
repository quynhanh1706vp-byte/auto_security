#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

pick_backup(){
  # pick the last known-good backup created BEFORE the indentation error patch
  ls -1t ${APP}.bak_top_handlers_v5_* 2>/dev/null | head -n 1 || true
}
B="$(pick_backup)"
if [ -z "${B:-}" ]; then
  echo "[ERR] cannot find ${APP}.bak_top_handlers_v5_* backup"
  exit 2
fi

cp -f "$B" "$APP"
echo "[RESTORE] $APP <= $B"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_AFTERREQ_ENDPOINT_HEADER_V1"
if MARK in s:
    print("[OK] after_request header already present")
    sys.exit(0)

block = f'''
# ===================== {MARK} =====================
from flask import request as _req
@app.after_request
def _vsp_after_request_endpoint_header(resp):
    try:
        if _req.path == "/api/vsp/top_findings_v1":
            ep = getattr(_req, "endpoint", None)
            if not ep:
                # flask stores endpoint on request.endpoint
                ep = getattr(_req, "endpoint", "") or ""
            resp.headers["X-VSP-ENDPOINT"] = str(ep or "")
    except Exception:
        pass
    return resp
# =================== /{MARK} ======================
'''

# Insert near bottom, before "if __name__" if exists; else append
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if m:
    s = s[:m.start()] + block + "\n" + s[m.start():]
else:
    s = s + "\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] inserted after_request endpoint header")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile (post-restore + header)"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC"
fi

echo "[STEP] detect real endpoint via header ..."
EP="$(
  curl -sS -D - -o /dev/null \
    "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
  | awk -F': ' 'tolower($1)=="x-vsp-endpoint"{gsub("\r","",$2); print $2}'
)"
echo "[INFO] X-VSP-ENDPOINT=$EP"
[ -n "${EP:-}" ] || { echo "[ERR] could not detect endpoint header"; exit 2; }

python3 - <<PY
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

ep = ${EP!r}
MARK="VSP_TOPFINDINGS_FIX_LIMIT_V6"

def locate_fn_for_endpoint(src: str, ep: str):
    # 1) endpoint == function name
    m = re.search(rf'(?m)^(\s*)def\s+{re.escape(ep)}\s*\(', src)
    if m:
        return ep
    # 2) endpoint specified in decorator: endpoint="..."
    m = re.search(rf'(?m)^\s*@app\.route\(\s*[\'"]\/api\/vsp\/top_findings_v1[\'"]\s*,.*endpoint\s*=\s*[\'"]{re.escape(ep)}[\'"]', src)
    if not m:
        return None
    after = src[m.end():]
    md = re.search(r'(?m)^\s*def\s+([a-zA-Z0-9_]+)\s*\(', after)
    return md.group(1) if md else None

fn = locate_fn_for_endpoint(s, ep)
if not fn:
    print("[ERR] cannot map endpoint to function:", ep)
    sys.exit(2)

print("[OK] endpoint maps to function:", fn)

# extract function block
mdef = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(.*\):\s*$', s)
if not mdef:
    print("[ERR] cannot find def for fn:", fn)
    sys.exit(2)

base_ind = mdef.group("ind")
start = mdef.start()
rest = s[mdef.end():]
mnext = re.search(rf'(?m)^{re.escape(base_ind)}def\s+\w+\s*\(', rest)
end = mdef.end() + (mnext.start() if mnext else len(rest))
chunk = s[start:end]

if f"{MARK}::{fn}" in chunk:
    print("[OK] already patched fn:", fn)
    sys.exit(0)

body_ind = base_ind + "    "
mdefline = re.search(rf'(?m)^{re.escape(base_ind)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk)
defline_end = mdefline.end()

# insert limit parsing right after def line (cap 500)
limit_block = (
    f"\n{body_ind}# {MARK}::{fn}\n"
    f"{body_ind}try:\n"
    f"{body_ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
    f"{body_ind}except Exception:\n"
    f"{body_ind}    _lim = 50\n"
    f"{body_ind}limit_applied = max(1, min(_lim, 500))\n"
)

early = chunk[defline_end:defline_end+1800]
if "limit_applied" not in early and "request.args.get('limit')" not in early:
    chunk = chunk[:defline_end] + limit_block + chunk[defline_end:]

# replace hard caps 50 inside this function chunk
repls = [
    (r'\[\s*:\s*50\s*\]', '[:limit_applied]'),
    (r'\[\s*0\s*:\s*50\s*\]', '[0:limit_applied]'),
    (r'range\s*\(\s*50\s*\)', 'range(limit_applied)'),
    (r'(\b(top_n|max_items|n|limit)\s*=\s*)50\b', r'\1limit_applied'),
    (r'(?m)^\s*limit_applied\s*=\s*50\s*$', f"{body_ind}limit_applied = limit_applied"),
    (r'(["\']limit_applied["\']\s*:\s*)50\b', r'\1limit_applied'),
]
for pat, rep in repls:
    chunk = re.sub(pat, rep, chunk)

# final guard before last return jsonify
lines = chunk.splitlines(True)
ret_i = None
for i in range(len(lines)-1, -1, -1):
    if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
        ret_i = i
        break
finalize = (
    f"{body_ind}# {MARK}::{fn} FINALIZE\n"
    f"{body_ind}try:\n"
    f"{body_ind}    if 'items' in locals() and isinstance(items, (list, tuple)):\n"
    f"{body_ind}        items = list(items)[:int(limit_applied)]\n"
    f"{body_ind}    else:\n"
    f"{body_ind}        items = []\n"
    f"{body_ind}    _total = locals().get('total', None)\n"
    f"{body_ind}    if isinstance(_total, int):\n"
    f"{body_ind}        items_truncated = bool(_total > len(items))\n"
    f"{body_ind}except Exception:\n"
    f"{body_ind}    pass\n"
)
if ret_i is not None:
    window = "".join(lines[max(0, ret_i-80):ret_i])
    if "FINALIZE" not in window:
        lines.insert(ret_i, finalize)
chunk = "".join(lines)

# add handler_used into response (best-effort after rid_used or rid)
chunk2 = re.sub(
    r'(?m)^(?P<ind>\s*)("rid_used"\s*:\s*[^,\n]+,\s*)$',
    rf'\g<ind>\2\g<ind>"handler_used": "{fn}",\n',
    chunk,
    count=1
)
if chunk2 == chunk:
    chunk2 = re.sub(
        r'(?m)^(?P<ind>\s*)("rid"\s*:\s*[^,\n]+,\s*)$',
        rf'\g<ind>\2\g<ind>"handler_used": "{fn}",\n',
        chunk,
        count=1
    )
chunk = chunk2

s2 = s[:start] + chunk + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched handler fn:", fn)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile (after limit patch)"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC"
fi

echo "[PROBE] top_findings_v1 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"handler_used=",j.get("handler_used"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'
