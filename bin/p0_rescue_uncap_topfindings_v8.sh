#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID:-VSP_CI_20251218_114312}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need awk; need curl

# 0) find newest backup that compiles
tmp="$(mktemp -d /tmp/vsp_rescue_v8_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

best=""
for f in $(ls -1t ${APP}.bak_* 2>/dev/null || true); do
  cp -f "$f" "$tmp/app.py"
  if python3 -m py_compile "$tmp/app.py" >/dev/null 2>&1; then
    best="$f"
    break
  fi
done

if [ -z "${best:-}" ]; then
  echo "[ERR] no compiling backup found for ${APP}.bak_*"
  echo "Tip: list backups: ls -1t ${APP}.bak_* | head"
  exit 2
fi

cp -f "$best" "$APP"
echo "[RESTORE] $APP <= $best"

# 1) patch all handlers that declare /api/vsp/top_findings_v1
python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_TOPFINDINGS_UNCAP50_V8"

# find decorators that mention this route (single-line decorators)
dec_pat = re.compile(r'(?m)^(?P<ind>\s*)@app\.(get|route)\(\s*[\'"]/api/vsp/top_findings_v1[\'"].*\)\s*$')
decs = list(dec_pat.finditer(s))
if not decs:
    print("[WARN] no single-line decorators found for /api/vsp/top_findings_v1 (may be multi-line).")
    # fallback: find any line containing it
    decs = list(re.finditer(r'(?m)^\s*@app\..*/api/vsp/top_findings_v1.*$', s))

patched = 0
for d in decs:
    # locate def right after decorator
    after = s[d.end():]
    md = re.search(r'(?m)^(?P<ind>\s*)def\s+(?P<fn>[a-zA-Z0-9_]+)\s*\(.*\):\s*$', after)
    if not md:
        continue
    fn = md.group("fn")
    base_ind = md.group("ind")
    def_start = d.end() + md.start()
    def_end_line = d.end() + md.end()

    # function block end: next def at same indent
    rest = s[def_end_line:]
    mnext = re.search(rf'(?m)^{re.escape(base_ind)}def\s+\w+\s*\(', rest)
    end = def_end_line + (mnext.start() if mnext else len(rest))
    chunk = s[def_start:end]

    if f"{MARK}::{fn}" in chunk:
        continue

    body = base_ind + "    "

    # insert limit_applied calc right after def line (NO try/except)
    insert = (
        f"\n{body}# {MARK}::{fn}\n"
        f"{body}_lim_s = (request.args.get('limit') or '50').strip()\n"
        f"{body}limit_applied = int(_lim_s) if _lim_s.isdigit() else 50\n"
        f"{body}limit_applied = max(1, min(limit_applied, 500))\n"
    )
    early = chunk[ (def_end_line - def_start) : (def_end_line - def_start) + 1800 ]
    if "limit_applied" not in early:
        chunk = chunk[:(def_end_line - def_start)] + insert + chunk[(def_end_line - def_start):]

    # remove/replace common 50 hard caps
    reps = [
        (r'\[\s*:\s*50\s*\]', '[:limit_applied]'),
        (r'\[\s*0\s*:\s*50\s*\]', '[0:limit_applied]'),
        (r'range\s*\(\s*50\s*\)', 'range(limit_applied)'),
        (r'(\b(top_n|max_items|n|limit)\s*=\s*)50\b', r'\1limit_applied'),
        (r'(["\']limit_applied["\']\s*:\s*)50\b', r'\1limit_applied'),
        # hard set limit_applied=50 lines → comment out (safe)
        (r'(?m)^(?P<ind>\s*)limit_applied\s*=\s*50\s*$', r'\g<ind># hardcap removed by V8'),
    ]
    for pat, rep in reps:
        chunk = re.sub(pat, rep, chunk)

    # final enforce slice before last return jsonify
    lines = chunk.splitlines(True)
    ret_i=None
    for i in range(len(lines)-1, -1, -1):
        if re.search(r'^\s*return\s+jsonify\s*\(', lines[i]):
            ret_i=i; break
    if ret_i is not None:
        window="".join(lines[max(0, ret_i-80):ret_i])
        if "enforce slice" not in window:
            enforce = (
                f"{body}# {MARK}::{fn} enforce slice\n"
                f"{body}if 'items' in locals() and isinstance(items, (list, tuple)):\n"
                f"{body}    items = list(items)[:limit_applied]\n"
            )
            lines.insert(ret_i, enforce)
            chunk="".join(lines)

    # best-effort: if response has "limit_applied": limit_applied now, good; else leave.
    s = s[:def_start] + chunk + s[end:]
    patched += 1

p.write_text(s, encoding="utf-8")
print("[OK] patched_handlers=", patched)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC ..."
  sudo systemctl restart "$SVC" || true
fi

echo "[PROBE] top_findings_v1 limit=200 ..."
curl -sS "$BASE/api/vsp/top_findings_v1?rid=$RID&limit=200" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"total=",j.get("total"),"limit_applied=",j.get("limit_applied"),"items_len=",len(j.get("items") or []),"items_truncated=",j.get("items_truncated"))'

echo "[DONE] Ctrl+F5 on UI."
