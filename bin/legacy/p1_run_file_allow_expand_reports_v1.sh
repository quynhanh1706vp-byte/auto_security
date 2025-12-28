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
cp -f "$W" "${W}.bak_allowrep_${TS}"
echo "[BACKUP] ${W}.bak_allowrep_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P1_RUN_FILE_ALLOW_REPORTS_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# Heuristic: find allowlist function/block for run_file_allow
# We patch by injecting a safe predicate near the top-level of run_file_allow handler:
# allow exactly known filenames and reports/findings_unified.(csv|sarif|html|pdf)
needle_candidates = [
    "def api_vsp_run_file_allow",
    "run_file_allow",
    "PATH_INFO\"") # fallback
]

# Find a good insertion point: near a check like `if not allowed: return {"ok":False,"err":"not allowed"}`
m = re.search(r'(not\s+allowed|err"\s*:\s*"not allowed"|return\s+_json\([^)]*not allowed)', s)
if not m:
    # fallback: search for function name and insert after it starts
    m = re.search(r"def\s+[^\\n]*run_file_allow[^\\n]*:\n", s)
if not m:
    print("[ERR] cannot locate run_file_allow block to patch safely")
    raise SystemExit(2)

# Insert a helper allow-path regex block near top of file (after imports) and then use it in run_file_allow logic.
# 1) Add helper definitions once (near beginning after imports).
ins_helper = r"""
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
        if not path: return False
        if path in _VSP_RUN_ALLOW_FILES_V1: return True
        return bool(_VSP_RUN_ALLOW_RE_V1.match(path))
    except Exception:
        return False
# ===================== /VSP_P1_RUN_FILE_ALLOW_REPORTS_V1 =====================
"""

if "VSP_P1_RUN_FILE_ALLOW_REPORTS_V1" not in s:
    # put helper after first import block
    im = re.search(r"(\nimport [^\n]+\n)+", s)
    if im:
        pos = im.end()
        s = s[:pos] + "\n" + ins_helper + "\n" + s[pos:]
    else:
        s = ins_helper + "\n" + s

# 2) Patch run_file_allow logic: if it has a variable `path` or similar, enforce via helper.
# We'll inject a guard snippet near beginning of the handler (first occurrence of `path =` inside handler).
defm = re.search(r"def\s+([^\n]*run_file_allow[^\n]*)\n", s)
if not defm:
    # sometimes it's wrapped; best effort: find first "path =" occurrence and inject before the first not-allowed return
    pass

# Inject guard before the first "not allowed" return: detect local var name `path` commonly.
guard = r"""
        # VSP_P1_RUN_FILE_ALLOW_REPORTS_V1: commercial allowlist (read-only)
        try:
            if not _vsp_run_file_allow_ok_v1(path):
                return {"ok": False, "err": "not allowed", "path": path}
        except Exception:
            return {"ok": False, "err": "not allowed", "path": (path if 'path' in locals() else None)}
"""

# Find a spot inside the handler where `path` is defined.
pm = re.search(r"\n(\s+)path\s*=\s*(.+)\n", s)
if pm:
    indent = pm.group(1)
    g = "\n".join((indent + line if line.strip() else line) for line in guard.splitlines())
    insert_at = pm.end()
    s = s[:insert_at] + g + "\n" + s[insert_at:]
else:
    # fallback: insert near first "not allowed" return and hope `path` exists
    na = re.search(r"\n(\s+)(return\s+\{[^\n]*not allowed[^\n]*\})", s)
    if na:
        indent = na.group(1)
        g = "\n".join((indent + line if line.strip() else line) for line in guard.splitlines())
        s = s[:na.start()] + "\n" + g + "\n" + s[na.start():]
    else:
        print("[ERR] could not find insertion point for allow guard")
        raise SystemExit(2)

p.write_text(s, encoding="utf-8")
print("[OK] patched allowlist for run_file_allow (reports + manifest files)")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: manifest should improve (lite) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"))'
echo "[DONE]"
