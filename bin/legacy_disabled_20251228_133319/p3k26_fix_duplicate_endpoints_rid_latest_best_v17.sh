#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v journalctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v grep >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

echo "== [0] stop + reset-failed (avoid restart burst) =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

echo "== [1] truncate errlog so we only see NEW crash (if any) =="
mkdir -p "$(dirname "$ERRLOG")"
: > "$ERRLOG" || true

echo "== [2] backup app =="
cp -f "$APP" "${APP}.bak_p3k26_v17_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v17_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

TAG = "P3K26_DEDUPE_RID_ENDPOINTS_V17"
TARGETS = ["api_vsp_rid_latest", "api_vsp_rid_best"]

decor_re = re.compile(r'^\s*@app\.(route|get|post|put|delete|patch)\b')
def_re   = re.compile(r'^\s*def\s+([A-Za-z_]\w*)\s*\(')

def find_decorated_def_blocks():
    blocks=[]
    i=0
    while i < len(lines):
        if decor_re.match(lines[i]):
            start=i
            j=i
            while j < len(lines) and decor_re.match(lines[j]):
                j += 1
            if j < len(lines):
                m = def_re.match(lines[j])
                if m:
                    name=m.group(1)
                    indent = len(lines[start]) - len(lines[start].lstrip())
                    blocks.append((start, j, name, indent))
                    i = j + 1
                    continue
        i += 1
    return blocks

def comment_block(start, indent):
    # comment from start until next top-level @app.* at <= indent
    k=start
    while k < len(lines):
        ln = lines[k]
        ind = len(ln) - len(ln.lstrip())
        if k != start and ind <= indent and ln.lstrip().startswith("@app."):
            break
        if not ln.lstrip().startswith("#"):
            lines[k] = "# " + ln
        k += 1
    lines.insert(start, f"# {TAG}: disabled duplicate block\n")

def comment_line(i, reason):
    if not lines[i].lstrip().startswith("#"):
        lines[i] = "# " + lines[i]
    lines.insert(i, f"# {TAG}: {reason}\n")

# 1) Deduplicate decorated defs by function name for TARGETS
blocks = find_decorated_def_blocks()
seen = {}
disabled_blocks = 0

# Work from bottom to top for safe insertion
for start, defidx, name, indent in sorted(blocks, key=lambda x: x[0], reverse=True):
    if name not in TARGETS:
        continue
    if name not in seen:
        seen[name] = start
        continue
    # duplicate => disable entire decorated block
    comment_block(start, indent)
    disabled_blocks += 1

# 2) Also comment out any add_url_rule() that explicitly sets endpoint to TARGETS
# (handles hidden registrations that bypass decorators)
add_url_pat = re.compile(r'\badd_url_rule\s*\(')
for t in TARGETS:
    ep_pat = re.compile(r'endpoint\s*=\s*[\'"]' + re.escape(t) + r'[\'"]')
    for i in range(len(lines)-1, -1, -1):
        if add_url_pat.search(lines[i]) and ep_pat.search(lines[i]):
            comment_line(i, f"disabled add_url_rule endpoint='{t}'")
            # do NOT count as block; just line-level
            break

# 3) If there are multiple plain 'def api_vsp_rid_latest' without decorators (rare), dedupe them too
for t in TARGETS:
    def_pat = re.compile(r'^\s*def\s+' + re.escape(t) + r'\s*\(')
    hits = [i for i,ln in enumerate(lines) if def_pat.match(ln)]
    if len(hits) > 1:
        # keep first, comment later ones (from bottom)
        for i in reversed(hits[1:]):
            # comment function body until next top-level def/@app
            indent = len(lines[i]) - len(lines[i].lstrip())
            k=i
            while k < len(lines):
                ln=lines[k]
                ind=len(ln) - len(ln.lstrip())
                if k!=i and ind<=indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@app.")):
                    break
                if not ln.lstrip().startswith("#"):
                    lines[k] = "# " + ln
                k += 1
            lines.insert(i, f"# {TAG}: disabled duplicate plain def '{t}'\n")
            disabled_blocks += 1

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] disabled_duplicate_blocks={disabled_blocks}")
PY

echo "== [3] py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [4] restart =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [5] show fresh errlog + journal tail =="
echo "--- tail errlog ---"
tail -n 120 "$ERRLOG" || true
echo "--- journal tail ---"
sudo journalctl -u "$SVC" -n 120 --no-pager | tail -n 120 || true

echo "== [6] smoke (3s each) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_latest" -o /tmp/rid_latest.json 2>&1 | sed -n '1,60p'
echo "--- /tmp/rid_latest.json ---"; head -c 220 /tmp/rid_latest.json || true; echo
curl -sv --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_best" -o /tmp/rid_best.json 2>&1 | sed -n '1,60p'
echo "--- /tmp/rid_best.json ---"; head -c 220 /tmp/rid_best.json || true; echo
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "--- head /tmp/vsp5.html ---"; head -n 25 /tmp/vsp5.html || true

echo "[DONE] p3k26_fix_duplicate_endpoints_rid_latest_best_v17"
