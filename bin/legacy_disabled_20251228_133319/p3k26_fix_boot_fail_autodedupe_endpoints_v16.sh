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
command -v grep >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

echo "== [0] show last boot errors (journal + errlog) =="
sudo journalctl -u "$SVC" -n 220 --no-pager | tail -n 120 || true
if [ -f "$ERRLOG" ]; then
  echo "== tail errlog =="
  tail -n 140 "$ERRLOG" || true
  echo "== grep TRACE/ERROR from errlog =="
  grep -nE "Traceback|AssertionError|Exception|ERROR|ImportError|ModuleNotFoundError|SyntaxError|IndentationError|KeyError|ValueError" "$ERRLOG" | tail -n 120 || true
else
  echo "(no $ERRLOG)"
fi

echo "== [1] backup app =="
cp -f "$APP" "${APP}.bak_p3k26_v16_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v16_${TS}"

echo "== [2] auto-dedupe Flask endpoint FUNCTION NAMES (most common overwrite cause) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

TAG="P3K26_AUTODEDUPE_ENDPOINTS_V16"

# Identify blocks: decorators (@app.*) immediately followed by def name(...)
decor_re = re.compile(r'^\s*@app\.(route|get|post|put|delete|patch)\b')
def_re   = re.compile(r'^\s*def\s+([A-Za-z_]\w*)\s*\(')

# Find (start_idx, def_idx, func_name, indent)
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

seen={}
disabled=0

def is_next_top_handler(k:int, base_indent:int)->bool:
    if k>=len(lines): return True
    ln=lines[k]
    ind = len(ln) - len(ln.lstrip())
    if ind<=base_indent and ln.lstrip().startswith("@app."):
        return True
    return False

# Disable duplicates of the SAME function name (Flask endpoint default = function name)
for start, defidx, name, indent in blocks:
    if name not in seen:
        seen[name]=start
        continue

# Disable from bottom to top so indexes stable
for start, defidx, name, indent in sorted(blocks, key=lambda x:x[0], reverse=True):
    if seen.get(name) != start:
        # comment out decorator+def+body until next top-level @app.* at <= indent
        k = start
        while k < len(lines):
            if k != start and is_next_top_handler(k, indent):
                break
            if not lines[k].lstrip().startswith("#"):
                lines[k] = "# " + lines[k]
            k += 1
        lines.insert(start, f"# {TAG}: disabled duplicate endpoint function '{name}'\n")
        disabled += 1

out="".join(lines)
p.write_text(out, encoding="utf-8")
print(f"[OK] disabled_duplicates={disabled} (by function-name)")
PY

echo "== [3] py_compile app =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [4] restart service =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [5] if still failing, print fresh traceback =="
sudo journalctl -u "$SVC" -n 220 --no-pager | tail -n 140 || true
if [ -f "$ERRLOG" ]; then tail -n 140 "$ERRLOG" || true; fi

echo "== [6] smoke basic endpoints (3s) =="
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/rid_best" | head -c 250; echo
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html && echo "[OK] /vsp5 fetched" || echo "[FAIL] /vsp5"
head -n 20 /tmp/vsp5.html 2>/dev/null || true

echo "[DONE] p3k26_fix_boot_fail_autodedupe_endpoints_v16"
