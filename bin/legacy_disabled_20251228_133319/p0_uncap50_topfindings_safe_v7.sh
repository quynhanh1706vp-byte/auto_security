#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_uncap50_safe_v7_${TS}"
echo "[BACKUP] ${APP}.bak_uncap50_safe_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

targets = [
  "api_vsp_top_findings_v1",
  "vsp_top_findings_v1_p0",
  "api_vsp_top_findings_v1_alias",
  "api_vsp_top_findings_v2",
  "api_vsp_top_findings_v3",
]

def get_block(src, fn):
    m = re.search(rf'(?m)^(?P<ind>\s*)def\s+{re.escape(fn)}\s*\(.*\):\s*$', src)
    if not m:
        return None
    base = m.group("ind")
    start = m.start()
    rest = src[m.end():]
    mnext = re.search(rf'(?m)^{re.escape(base)}def\s+\w+\s*\(', rest)
    end = m.end() + (mnext.start() if mnext else len(rest))
    return start, end, base, src[start:end]

def patch_chunk(chunk, base_ind, fn):
    MARK=f"VSP_UNCAP50_SAFE_V7::{fn}"
    if MARK in chunk:
        return chunk, False

    body = base_ind + "    "

    # Insert limit_applied calc right after def line (NO try/except)
    mdefline = re.search(rf'(?m)^{re.escape(base_ind)}def\s+{re.escape(fn)}\s*\(.*\):\s*$', chunk)
    if not mdefline:
        return chunk, False

    defline_end = mdefline.end()
    early = chunk[defline_end:defline_end+1800]

    if "limit_applied" not in early:
        block = (
            f"\n{body}# {MARK}\n"
            f"{body}_lim_s = (request.args.get('limit') or '50').strip()\n"
            f"{body}limit_applied = int(_lim_s) if _lim_s.isdigit() else 50\n"
            f"{body}limit_applied = max(1, min(limit_applied, 500))\n"
        )
        chunk = chunk[:defline_end] + block + chunk[defline_end:]

    # Replace hard caps 50 -> limit_applied
    reps = [
        (r'\[\s*:\s*50\s*\]', '[:limit_applied]'),
        (r'\[\s*0\s*:\s*50\s*\]', '[0:limit_applied]'),
        (r'range\s*\(\s*50\s*\)', 'range(limit_applied)'),
        (r'(\b(top_n|max_items|n|limit)\s*=\s*)50\b', r'\1limit_applied'),
        (r'(["\']limit_applied["\']\s*:\s*)50\b', r'\1limit_applied'),
        (r'(?m)^\s*limit_applied\s*=\s*50\s*$', f"{body}limit_applied = limit_applied"),
    ]
    for pat, rep in reps:
        chunk = re.sub(pat, rep, chunk)

    # Final enforce before last return jsonify: items = items[:limit_applied] (NO try/except)
    lines = chunk.splitlines(True)
    ret_i=None
    for i in range(len(lines)-1, -1, -1):
        if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
            ret_i=i; break
    if ret_i is not None:
        window="".join(lines[max(0,ret_i-80):ret_i])
        if "items = list(items)[:limit_applied]" not in window and "enforce slice" not in window:
            enforce = (
                f"{body}# {MARK} enforce slice\n"
                f"{body}if 'items' in locals() and isinstance(items, (list, tuple)):\n"
                f"{body}    items = list(items)[:limit_applied]\n"
            )
            lines.insert(ret_i, enforce)
            chunk="".join(lines)

    return chunk, True

changed_any=False
patched=[]
for fn in targets:
    blk = get_block(s, fn)
    if not blk:
        continue
    start,end,base,chunk = blk
    chunk2, changed = patch_chunk(chunk, base, fn)
    if changed:
        s = s[:start] + chunk2 + s[end:]
        changed_any=True
        patched.append(fn)

p.write_text(s, encoding="utf-8")
print("[OK] changed_any=", changed_any, "patched=", patched)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v1 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'
