#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_topv3_contract_${TS}"
echo "[BACKUP] ${APP}.bak_topv3_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

fn="api_vsp_top_findings_v3"
mdef=re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(.*\):\s*$', s)
if not mdef:
    print("[ERR] missing def", fn); sys.exit(2)

base=mdef.group("ind")
start=mdef.start()
rest=s[mdef.end():]
mnext=re.search(rf'(?m)^{re.escape(base)}def\s+\w+\s*\(', rest)
end=mdef.end()+(mnext.start() if mnext else len(rest))
chunk=s[start:end]

MARK="VSP_TOPFINDINGS_V3_CONTRACT_V1"
if MARK in chunk:
    print("[OK] already patched", MARK); sys.exit(0)

body=base+"    "

# Ensure limit_applied defined near top (safe, no try/except)
mdefline=re.search(rf'(?m)^{re.escape(base)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk)
defline_end=mdefline.end()

early=chunk[defline_end:defline_end+1800]
if "limit_applied" not in early:
    blk=(
        f"\n{body}# {MARK}\n"
        f"{body}_lim_s = (request.args.get('limit') or '200').strip()\n"
        f"{body}limit_applied = int(_lim_s) if _lim_s.isdigit() else 200\n"
        f"{body}limit_applied = max(1, min(limit_applied, 500))\n"
    )
    chunk=chunk[:defline_end]+blk+chunk[defline_end:]

# Before last return jsonify, enforce: total/items_len/items_truncated/limit_applied
lines=chunk.splitlines(True)
ret_i=None
for i in range(len(lines)-1,-1,-1):
    if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
        ret_i=i; break
if ret_i is None:
    print("[ERR] no return jsonify found in", fn); sys.exit(2)

window="".join(lines[max(0,ret_i-120):ret_i])
if "items_truncated" not in window and MARK not in window:
    inject=(
        f"{body}# {MARK} finalize contract fields\n"
        f"{body}if 'items' in locals() and isinstance(items, (list, tuple)):\n"
        f"{body}    items = list(items)\n"
        f"{body}else:\n"
        f"{body}    items = []\n"
        f"{body}total = len(items)\n"
        f"{body}items_truncated = False\n"
        f"{body}if len(items) > limit_applied:\n"
        f"{body}    items = items[:limit_applied]\n"
        f"{body}    items_truncated = True\n"
    )
    lines.insert(ret_i, inject)

chunk="".join(lines)

# Ensure response dict includes these keys (best-effort)
# Replace common dict literals: add fields if "items": items is present
chunk2=chunk
chunk2=re.sub(r'(?m)^(?P<ind>\s*)("items"\s*:\s*items\s*,\s*)$',
              rf'\g<ind>\2\g<ind>"total": total,\n\g<ind>"limit_applied": limit_applied,\n\g<ind>"items_truncated": items_truncated,\n',
              chunk2, count=1)
chunk = chunk2

s2=s[:start]+chunk+s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", MARK, "in", fn)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v3 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v3?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'
