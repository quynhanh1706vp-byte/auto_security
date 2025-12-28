#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v grep >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p3k26_v15_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v15_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

TAG = "P3K26_DEDUPE_RID_BEST_V15"
pat = re.compile(r'''@app\.(get|route)\(\s*['"]/api/vsp/rid_best['"]''')

# Find all occurrences of the decorator line
hits = [i for i,ln in enumerate(lines) if pat.search(ln)]
print("rid_best_decorator_hits=", len(hits), "lines=", [h+1 for h in hits[:10]])

if len(hits) <= 1:
    print("[OK] no duplicate rid_best decorator found; nothing to do")
    raise SystemExit(0)

# Keep the first hit, disable the rest by commenting out the whole block
# Block = decorator line + function def body until next top-level decorator (@app./@bp./@blueprint.) or EOF
def is_top_deco(ln: str) -> bool:
    s = ln.lstrip()
    # top-level (no indent) decorator is common; but also accept same indent as the decorator we found
    return s.startswith("@app.") or s.startswith("@bp.") or s.startswith("@blueprint.")

def comment_block(start: int):
    # determine indent of decorator line
    indent = len(lines[start]) - len(lines[start].lstrip())
    i = start
    # comment decorator line and following lines until next decorator at same or lower indent
    while i < len(lines):
        ln = lines[i]
        # stop when we meet another decorator at indentation <= current decorator indent (top-level next handler)
        if i != start:
            if (len(ln) - len(ln.lstrip())) <= indent and ln.lstrip().startswith("@") and is_top_deco(ln):
                break
        if TAG not in ln:
            if ln.startswith("#"):
                lines[i] = ln  # keep comment
            else:
                lines[i] = "# " + ln
        i += 1
    # add tag marker at block start (commented)
    if not lines[start].lstrip().startswith(f"# {TAG}"):
        lines.insert(start, f"# {TAG}: disabled duplicate /api/vsp/rid_best block\n")
    return

# Disable from second occurrence onward (iterate from last to first so indexes stable when inserting)
for idx in reversed(hits[1:]):
    comment_block(idx)

out = "".join(lines)
p.write_text(out, encoding="utf-8")
print("[OK] wrote file with duplicates disabled")
PY

echo "== [py_compile] =="
python3 -m py_compile "$APP"
echo "[OK] vsp_demo_app.py compiles"

echo "== [restart] =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [smoke] /api/vsp/rid_best =="
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_best" | head -c 300; echo
echo "== [smoke] /vsp5 headers (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "== head /tmp/vsp5.html =="
head -n 15 /tmp/vsp5.html || true

echo "[DONE] p3k26_fix_duplicate_rid_best_endpoint_v15"
