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
MARK="VSP_P0_ALLOWLIST_ADD_FINDINGS_PAGE_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_allow_fp_${TS}"
echo "[BACKUP] ${W}.bak_allow_fp_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P0_ALLOWLIST_ADD_FINDINGS_PAGE_V1"
if mark in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

TARGET = "/api/vsp/findings_page"
changed = 0

if TARGET in s:
    print("[OK] target path already appears in file (may still be blocked, but skip text insert)")
    # still add marker to avoid re-run loops
    s = s + f"\n# ===================== {mark} (already had target string) =====================\n"
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] marker appended only")
    raise SystemExit(0)

# (A) Insert after '/api/vsp/runs', in list/tuple/set literals (string followed by comma)
def repl_runs_comma(m):
    q = m.group(1)
    return f"{q}/api/vsp/runs{q}, {q}{TARGET}{q},"
pat_a = re.compile(r"([\"'])/api/vsp/runs\1\s*,")
s2, n = pat_a.subn(repl_runs_comma, s, count=4)  # cap to avoid runaway
if n:
    s = s2
    changed += n

# (B) Insert after .add('/api/vsp/runs') lines
pat_b = re.compile(r"(?m)^(\s*)([A-Za-z_][A-Za-z0-9_\.]*)\.add\(\s*([\"'])/api/vsp/runs\3\s*\)\s*$")
def repl_add(m):
    indent, var, q = m.group(1), m.group(2), m.group(3)
    return m.group(0) + f"\n{indent}{var}.add({q}{TARGET}{q})"
s2, n = pat_b.subn(repl_add, s, count=6)
if n:
    s = s2
    changed += n

# (C) Insert dict allow entry: '/api/vsp/runs': True
pat_c = re.compile(r"([\"'])/api/vsp/runs\1\s*:\s*True")
def repl_dict(m):
    q = m.group(1)
    return m.group(0) + f", {q}{TARGET}{q}: True"
s2, n = pat_c.subn(repl_dict, s, count=3)
if n:
    s = s2
    changed += n

s = s + f"\n# ===================== {mark} =====================\n# inserted allow for {TARGET}\n# changes={changed}\n# ===================== /{mark} =====================\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] allowlist patched in file; changed_tokens=", changed)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke SAFE after allowlist patch =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/p0_smoke_findings_page_safe_v1.sh || true

echo "[DONE]"
