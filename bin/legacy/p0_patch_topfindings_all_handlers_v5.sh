#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_top_handlers_v5_${TS}"
echo "[BACKUP] ${APP}.bak_top_handlers_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

targets = [
  "api_vsp_top_findings_v1",
  "vsp_top_findings_v1_p0",
  "api_vsp_top_findings_v1_alias",
  # bonus: nếu có các phiên bản khác vẫn bị route lặp
  "api_vsp_top_findings_v2",
  "api_vsp_top_findings_v3",
]

def find_block(src: str, fn: str):
    mdef = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(.*\):\s*$', src)
    if not mdef:
        return None
    base_ind = mdef.group("ind")
    start = mdef.start()
    rest = src[mdef.end():]
    mnext = re.search(rf'(?m)^{re.escape(base_ind)}def\s+\w+\s*\(', rest)
    end = mdef.end() + (mnext.start() if mnext else len(rest))
    return start, end, base_ind

def patch_fn(src: str, fn: str):
    loc = find_block(src, fn)
    if not loc:
        return src, False
    start, end, base_ind = loc
    chunk = src[start:end]
    MARK = f"VSP_TOPFINDINGS_ALL_V5::{fn}"
    if MARK in chunk:
        return src, False

    body_ind = base_ind + "    "
    # def line end
    mdefline = re.search(rf'(?m)^{re.escape(base_ind)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk)
    if not mdefline:
        return src, False
    defline_end = mdefline.end()

    # 1) Insert limit parsing early (cap 500)
    early = chunk[defline_end:defline_end+1600]
    if ("request.args.get('limit')" not in early) and ('request.args.get("limit")' not in early):
        limit_block = (
            f"\n{body_ind}# {MARK}\n"
            f"{body_ind}try:\n"
            f"{body_ind}    _lim = int((request.args.get('limit') or '50').strip())\n"
            f"{body_ind}except Exception:\n"
            f"{body_ind}    _lim = 50\n"
            f"{body_ind}limit = max(1, min(_lim, 500))\n"
            f"{body_ind}limit_applied = limit\n"
        )
        chunk = chunk[:defline_end] + limit_block + chunk[defline_end:]
    else:
        # still ensure limit_applied exists (some funcs only have limit)
        if re.search(r'(?m)^\s*limit_applied\s*=', early) is None:
            chunk = chunk[:defline_end] + f"\n{body_ind}limit_applied = int(locals().get('limit', 50))\n" + chunk[defline_end:]

    # 2) Replace hard caps 50 inside THIS function
    repls = [
        (r'\[\s*:\s*50\s*\]', '[:limit_applied]'),
        (r'\[\s*0\s*:\s*50\s*\]', '[0:limit_applied]'),
        (r'range\s*\(\s*50\s*\)', 'range(limit_applied)'),
        (r'(\b(top_n|max_items|n|limit)\s*=\s*)50\b', r'\1limit_applied'),
        (r'min\s*\(\s*limit\s*,\s*50\s*\)', 'min(limit, 500)'),
        (r'min\s*\(\s*limit_applied\s*,\s*50\s*\)', 'min(limit_applied, 500)'),
    ]
    for pat, rep in repls:
        chunk = re.sub(pat, rep, chunk)

    # 3) Replace JSON literal "limit_applied": 50 -> limit_applied
    chunk = re.sub(r'(["\']limit_applied["\']\s*:\s*)50\b', r'\1limit_applied', chunk)
    chunk = re.sub(r'(?m)^\s*limit_applied\s*=\s*50\s*$', f"{body_ind}limit_applied = limit_applied", chunk)

    # 4) Insert final guard before last return jsonify
    lines = chunk.splitlines(True)
    ret_i = None
    for i in range(len(lines)-1, -1, -1):
        if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
            ret_i = i
            break

    finalize = (
        f"{body_ind}# {MARK} FINALIZE\n"
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

    # 5) Inject handler_used into response dict if we can find a stable anchor
    # try after "rid_used": ...,
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

    src2 = src[:start] + chunk + src[end:]
    return src2, True

changed_any = False
for fn in targets:
    s, changed = patch_fn(s, fn)
    changed_any = changed_any or changed

p.write_text(s, encoding="utf-8")
print("[OK] patched_any=", changed_any)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v1 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"handler_used=",j.get("handler_used"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'
