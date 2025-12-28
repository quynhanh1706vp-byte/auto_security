#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_runs_reports_bp.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs500guard_${TS}"
echo "[BACKUP] ${F}.bak_runs500guard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_runs_reports_bp.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_500_GUARD_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# --- 1) ensure safe helper exists ---
if "def _safe_exists(" not in s:
    inject = r'''
# === VSP_P1_RUNS_500_GUARD_V1 ===
def _safe_exists(_p):
    try:
        return bool(_p) and _p.exists() and _p.is_file()
    except Exception:
        return False

def _safe_int(x, d=0):
    try:
        return int(x)
    except Exception:
        return d
# === /VSP_P1_RUNS_500_GUARD_V1 ===
'''
    # place after imports (first 120 lines)
    lines=s.splitlines(True)
    ins=0
    for i,l in enumerate(lines[:160]):
        if l.startswith("import ") or l.startswith("from "):
            ins=i+1
    lines.insert(ins, inject+"\n")
    s="".join(lines)

# --- 2) harden _has() if present ---
# replace any ".exists()" usage on weird tuples by forcing _safe_exists(path)
# (simple but effective: convert (run_dir/"X").exists() into _safe_exists(run_dir/"X"))
s = re.sub(r'(\(\s*run_dir\s*/\s*["\'][^"\']+["\']\s*\))\.exists\(\)', r'_safe_exists\1', s)
s = re.sub(r'(\(\s*reports_dir\s*/\s*["\'][^"\']+["\']\s*\))\.exists\(\)', r'_safe_exists\1', s)

# --- 3) wrap api_runs handler so it NEVER throws 500 ---
m = re.search(r'@bp\.get\(\s*["\']/api/vsp/runs["\']\s*\)\s*\ndef\s+api_runs\s*\(\s*\)\s*:\s*\n', s)
if not m:
    raise SystemExit("[ERR] cannot locate api_runs() handler")

# find api_runs() block indentation and body start
start = m.end()
# naive block end: next decorator or EOF
m2 = re.search(r'^\s*@bp\.get\(|^\s*@bp\.post\(|^\s*@bp\.route\(', s[start:], flags=re.M)
end = start + (m2.start() if m2 else len(s[start:]))

block = s[start:end]
# indent of first line in block
first_line = block.splitlines(True)[0]
indent = re.match(r'^(\s*)', first_line).group(1)

# wrap existing body in try/except if not already
if "try:" not in block[:300]:
    wrapped = f"""{indent}    try:
{block}{indent}    except Exception as e:
{indent}        # commercial-safe: never 500 HTML; return JSON with error + empty items
{indent}        try:
{indent}            import traceback
{indent}            tb = traceback.format_exc().splitlines()[-12:]
{indent}        except Exception:
{indent}            tb = [str(e)]
{indent}        return jsonify({{"ok": False, "who": "{MARK}", "error": "RUNS_INTERNAL_ERROR", "items": [], "items_len": 0, "trace_tail": tb}}), 200
"""
    # NOTE: block already contains indentation 4 spaces inside def; we inserted extra 4 -> use as-is
    # But our wrapped includes original 'block' which already begins with 4 spaces; so we must not double-indent it.
    # Fix: recompose correctly: keep original block, but indent it one level under try by adding 4 spaces.
    blines = block.splitlines(True)
    blines = [("    "+l if l.strip() else l) for l in blines]  # add 4 spaces
    block_try = "".join(blines)
    wrapped = f"""{indent}    try:
{block_try}{indent}    except Exception as e:
{indent}        try:
{indent}            import traceback
{indent}            tb = traceback.format_exc().splitlines()[-12:]
{indent}        except Exception:
{indent}            tb = [str(e)]
{indent}        return jsonify({{"ok": False, "who": "{MARK}", "error": "RUNS_INTERNAL_ERROR", "items": [], "items_len": 0, "trace_tail": tb}}), 200
"""
    s = s[:start] + wrapped + s[end:]

s = s + f"\n# {MARK}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile vsp_runs_reports_bp.py
echo "[OK] py_compile OK: vsp_runs_reports_bp.py"

sudo systemctl restart vsp-ui-8910.service
sleep 1

echo "== smoke: /api/vsp/runs MUST be JSON (no HTML 500) =="
curl -sS -i http://127.0.0.1:8910/api/vsp/runs?limit=1 | head -n 25
