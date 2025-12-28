#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_RUN_FILE_ALLOW_REPORTS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_allowrep_fix2_${TS}"
echo "[BACKUP] ${W}.bak_allowrep_fix2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RUN_FILE_ALLOW_REPORTS_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

helper = r'''
# ===================== VSP_P1_RUN_FILE_ALLOW_REPORTS_V1 =====================
# Expand allowed run_file_allow paths for commercial UI (read-only reports)
import re as _re_vsp_allowrep
_VSP_RUN_ALLOW_FILES_V1 = {
    "run_gate.json",
    "run_gate_summary.json",
    "SUMMARY.txt",
    "run_manifest.json",
    "run_evidence_index.json",
    "findings_unified.json",
}
_VSP_RUN_ALLOW_RE_V1 = _re_vsp_allowrep.compile(r"^(reports/findings_unified\.(csv|sarif|html|pdf))$")
def _vsp_run_file_allow_ok_v1(path: str) -> bool:
    try:
        if not path:
            return False
        if path in _VSP_RUN_ALLOW_FILES_V1:
            return True
        return bool(_VSP_RUN_ALLOW_RE_V1.match(path))
    except Exception:
        return False
# ===================== /VSP_P1_RUN_FILE_ALLOW_REPORTS_V1 =====================
'''.strip("\n")

# 1) Insert helper after initial import block (best effort)
# Find the end of consecutive import/from lines near the top.
top = s[:6000]
lines = top.splitlines(True)
pos = 0
seen_import = False
for ln in lines:
    if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+)\S+', ln):
        seen_import = True
        pos += len(ln)
        continue
    # allow blank/comment lines immediately after imports
    if seen_import and re.match(r'^\s*(#.*)?$', ln):
        pos += len(ln)
        continue
    break

if pos <= 0:
    pos = 0

s = s[:pos] + ("\n" if pos and not s[:pos].endswith("\n") else "") + helper + "\n\n" + s[pos:]

# 2) Find run_file_allow handler region and inject guard after path variable assignment
# Locate by endpoint string first (most stable)
idx = s.find("/api/vsp/run_file_allow")
if idx < 0:
    # fallback: function name contains run_file_allow
    m = re.search(r"def\s+\w*run_file_allow\w*\s*\(", s)
    idx = m.start() if m else -1
if idx < 0:
    print("[ERR] cannot locate run_file_allow handler in file")
    raise SystemExit(2)

window = s[idx: idx + 12000]  # scan next ~12k chars
# Find first assignment of a plausible path variable
pm = re.search(r'^\s*(path|rel_path|req_path)\s*=\s*.*$', window, re.M)
varname = None
if pm:
    varname = pm.group(1)
    # compute absolute insertion position right after that line
    abs_line_start = idx + pm.start()
    abs_line_end = idx + pm.end()
    # determine indent from that line
    line = window[pm.start():pm.end()]
    indent = re.match(r'^(\s*)', line).group(1)
else:
    # fallback: find any "path =" even if indented weirdly
    pm = re.search(r'^\s*path\s*=\s*.*$', window, re.M)
    if pm:
        varname = "path"
        abs_line_end = idx + pm.end()
        line = window[pm.start():pm.end()]
        indent = re.match(r'^(\s*)', line).group(1)
    else:
        print("[ERR] cannot find path assignment near run_file_allow handler")
        raise SystemExit(2)

guard_tpl = f"""
{indent}# VSP_P1_RUN_FILE_ALLOW_REPORTS_V1: commercial allowlist (read-only)
{indent}try:
{indent}    if not _vsp_run_file_allow_ok_v1({varname}):
{indent}        return {{"ok": False, "err": "not allowed", "path": {varname}}}
{indent}except Exception:
{indent}    return {{"ok": False, "err": "not allowed", "path": ({varname} if '{varname}' in locals() else None)}}
""".rstrip("\n")

s = s[:abs_line_end] + "\n" + guard_tpl + "\n" + s[abs_line_end:]

p.write_text(s, encoding="utf-8")
print("[OK] patched run_file_allow allowlist (reports + manifest files)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: manifest should improve (lite) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"))'

echo "[DONE]"
