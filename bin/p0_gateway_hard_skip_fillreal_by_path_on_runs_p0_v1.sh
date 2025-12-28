#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_skip_fillreal_by_path_${TS}"
echo "[BACKUP] ${F}.bak_skip_fillreal_by_path_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_SKIP_FILLREAL_BY_PATH_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) inject helper after imports (safe, global scope)
lines = s.splitlines(True)
ins_at = 0
for i, ln in enumerate(lines[:300]):  # only scan top area
    if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', ln) or re.match(r'^\s*#', ln) or ln.strip()=="":
        ins_at = i+1
        continue
    break

helper = f"""
def _vsp_is_runs_path(environ):
    \"\"\"Return True if request path is /runs or /runs/... (standalone runs page).\"\"\"
    try:
        path = (environ.get("PATH_INFO") or "")
    except Exception:
        path = ""
    return path == "/runs" or path.startswith("/runs/")

# {MARK}
"""
lines.insert(ins_at, helper)
s = "".join(lines)

# 2) add guard into ANY if(...) that checks vsp_fill_real_data_5tabs_p1_v1.js not in html
def patch_if_line(m):
    indent = m.group("indent")
    cond = m.group("cond")
    if "_vsp_is_runs_path" in cond:
        return m.group(0)
    return f'{indent}if ({cond} and (not _vsp_is_runs_path(environ))):'

pat = re.compile(
    r'^(?P<indent>\s*)if\s*\(\s*(?P<cond>[^)]*vsp_fill_real_data_5tabs_p1_v1\.js[^)]*)\)\s*:\s*$',
    re.M
)
s2, n1 = pat.subn(patch_if_line, s)

# 3) defensive: variants without parentheses: if "vsp_fill_real..." not in html:
def patch_if_plain(m):
    indent = m.group("indent")
    cond = m.group("cond").strip()
    if "_vsp_is_runs_path" in cond:
        return m.group(0)
    return f'{indent}if ({cond}) and (not _vsp_is_runs_path(environ)):'  # keep colon

pat2 = re.compile(
    r'^(?P<indent>\s*)if\s+(?P<cond>.*vsp_fill_real_data_5tabs_p1_v1\.js.*not\s+in\s+html.*)\s*:\s*$',
    re.M
)
s3, n2 = pat2.subn(patch_if_plain, s2)

p.write_text(s3, encoding="utf-8")
print(f"[OK] patched {p} (if_paren_fixed={n1}, if_plain_fixed={n2})")
PY

# restart (reuse your stable launcher)
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs no fillreal injector =="
curl -sS http://127.0.0.1:8910/runs | grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" \
  && echo "[ERR] still injected" || echo "[OK] no fillreal on /runs"

echo "== sanity =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,8p'
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,12p'
