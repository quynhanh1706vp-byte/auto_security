#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_canonrid_${TS}"
echo "[BACKUP] ${F}.bak_canonrid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUN_FILE_CANON_RID_P0_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

# locate /api/vsp/run_file route handler function block
m = re.search(r'@app\.route\(\s*[\'"]/api/vsp/run_file[\'"][\s\S]*?\)\s*\n(\s*)def\s+([a-zA-Z0-9_]+)\s*\(', s)
if not m:
    print("[ERR] cannot locate /api/vsp/run_file handler in vsp_demo_app.py")
    raise SystemExit(2)

func_indent = m.group(1)
func_name = m.group(2)
start = m.start()

# find rid parsing inside this function (search after decorator)
sub = s[m.end():]
mr = re.search(r'^\s*rid\s*=\s*request\.args\.get\(\s*[\'"]rid[\'"]\s*\)[^\n]*$', sub, flags=re.M)
if not mr:
    print("[ERR] cannot locate rid = request.args.get('rid') inside", func_name)
    raise SystemExit(3)

ins_pos = m.end() + mr.end()
rid_line = mr.group(0)
rid_indent = re.match(r'^(\s*)', rid_line).group(1)

inject = f"""
{rid_indent}# {MARK}
{rid_indent}# Canonicalize RID for filesystem lookup:
{rid_indent}#   e.g. btl86-connector_RUN_YYYYmmdd_HHMMSS_xxxxxx  -> RUN_YYYYmmdd_HHMMSS_xxxxxx
{rid_indent}try:
{rid_indent}    _rid0 = (rid or "").strip()
{rid_indent}    _cands = [_rid0]
{rid_indent}    if "RUN_" in _rid0:
{rid_indent}        _cands.append(_rid0[_rid0.find("RUN_"):])
{rid_indent}    # pick first existing directory under SECURITY_BUNDLE/out or out_ci
{rid_indent}    from pathlib import Path as _P
{rid_indent}    _root = _P("/home/test/Data/SECURITY_BUNDLE")
{rid_indent}    _picked = None
{rid_indent}    for _cand in _cands:
{rid_indent}        if not _cand:
{rid_indent}            continue
{rid_indent}        for _base in ("out", "out_ci"):
{rid_indent}            _d = _root / _base / _cand
{rid_indent}            if _d.is_dir():
{rid_indent}                _picked = _cand
{rid_indent}                break
{rid_indent}        if _picked:
{rid_indent}            break
{rid_indent}    if _picked and _picked != rid:
{rid_indent}        rid = _picked
{rid_indent}except Exception:
{rid_indent}    pass
"""

s2 = s[:ins_pos] + inject + s[ins_pos:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched", MARK, "in", p, "handler:", func_name)
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile: vsp_demo_app.py"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8
curl -sS -I http://127.0.0.1:8910/vsp5 | head -n 12

echo "== verify run_file for prefixed RID =="
BASE="http://127.0.0.1:8910"
RID="btl86-connector_RUN_20251127_095755_000599"
for rel in "reports/index.html" "reports/run_gate_summary.json" "reports/findings_unified.json" "reports/SUMMARY.txt"; do
  code="$(curl -sS -o /dev/null -w "%{http_code}" "$BASE/api/vsp/run_file?rid=$RID&name=$rel" || true)"
  echo "$rel -> $code"
done
