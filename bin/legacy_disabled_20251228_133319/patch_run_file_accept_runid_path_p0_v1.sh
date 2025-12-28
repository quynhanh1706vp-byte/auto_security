#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# candidate backends (tùy bạn đã gắn route ở đâu)
CANDS=("vsp_demo_app.py" "wsgi_vsp_ui_gateway.py")
FOUND=""

for f in "${CANDS[@]}"; do
  if [ -f "$f" ] && grep -qE 'route\(.*/api/vsp/run_file' "$f"; then
    FOUND="$f"
    break
  fi
done

[ -n "${FOUND:-}" ] || { echo "[ERR] cannot find /api/vsp/run_file route in: ${CANDS[*]}"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$FOUND" "${FOUND}.bak_runfile_compat_${TS}"
echo "[BACKUP] ${FOUND}.bak_runfile_compat_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path(__import__("os").environ["FOUND"])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUN_FILE_COMPAT_RUNID_PATH_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# find handler function after @app.route("/api/vsp/run_file"...)
m = re.search(r'@app\.route\(\s*[\'"]/api/vsp/run_file[\'"][\s\S]*?\)\s*\n(\s*)def\s+([a-zA-Z0-9_]+)\s*\(\s*\)\s*:\s*\n', s)
if not m:
    print("[ERR] cannot locate run_file handler def after route decorator")
    raise SystemExit(3)

indent = m.group(1)
fn = m.group(2)

inject = f"""{indent}  # {MARK}
{indent}  # Accept both styles:
{indent}  #   new: ?rid=RUN_...&name=reports/...
{indent}  #   old: ?run_id=RUN_...&path=reports/...
{indent}  rid = request.args.get('rid') or request.args.get('run_id') or request.args.get('runId')
{indent}  name = request.args.get('name') or request.args.get('path') or request.args.get('file')
{indent}  # normalize to the canonical keys so downstream logic works
{indent}  if rid is not None and request.args.get('rid') is None:
{indent}    try:
{indent}      request.args = request.args.copy()
{indent}      request.args['rid'] = rid
{indent}    except Exception:
{indent}      pass
{indent}  if name is not None and request.args.get('name') is None:
{indent}    try:
{indent}      request.args = request.args.copy()
{indent}      request.args['name'] = name
{indent}    except Exception:
{indent}      pass
"""

# insert inject right after def line
pos = m.end()
s2 = s[:pos] + inject + s[pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", p, "function:", fn)
PY
FOUND="$FOUND" python3 - <<'PY'
# no-op: env pass for above
PY

python3 -m py_compile "$FOUND" && echo "[OK] py_compile: $FOUND"
echo "[NEXT] sudo systemctl restart vsp-ui-8910.service"
