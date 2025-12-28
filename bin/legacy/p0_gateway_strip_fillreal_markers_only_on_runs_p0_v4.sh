#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_strip_markers_runs_${TS}"
echo "[BACKUP] ${F}.bak_strip_markers_runs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_STRIP_FILLREAL_MARKERS_ON_RUNS_V4"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Must exist
if "_vsp_mw_strip_fillreal_on_runs" not in s:
    print("[ERR] _vsp_mw_strip_fillreal_on_runs not found; MW not installed yet")
    raise SystemExit(2)

# Insert marker-strips right after the existing script-strip re.sub (before `if html2 != html:`)
# We look for the specific block that strips the script and then checks html2 != html.
pat = re.compile(
    r"""
    (?P<head>
        html2\s*=\s*re\.sub\(
        .*?vsp_fill_real_data_5tabs_p1_v1\.js.*?
        \)\s*
    )
    (?P<mid>
        \s*if\s+html2\s*!=\s*html\s*:
    )
    """,
    re.S | re.X
)

def repl(m):
    head = m.group("head")
    mid = m.group("mid")
    inject = r"""
                # strip gateway marker comments too (runs-only)
                html2 = re.sub(r"\s*<!--\s*VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\s*-->\s*", "", html2, flags=re.I)
                html2 = re.sub(r"\s*<!--\s*/VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY\s*-->\s*", "", html2, flags=re.I)
                # """ + MARK + "\n"
    return head + inject + mid

s2, n = pat.subn(repl, s, count=1)
if n != 1:
    print(f"[ERR] patch pattern not found or ambiguous (n={n})")
    raise SystemExit(3)

# stamp marker once
s2 += f"\n# {MARK}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] injected marker strip into MW")
PY

rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== verify /runs clean (no marker, no script) =="
curl -sS http://127.0.0.1:8910/runs -o /tmp/runs.html
grep -n "VSP_FILL_REAL_DATA_5TABS_P1_V1_GATEWAY" /tmp/runs.html && echo "[ERR] marker still present" || echo "[OK] no marker"
grep -n "vsp_fill_real_data_5tabs_p1_v1\\.js" /tmp/runs.html && echo "[ERR] script still present" || echo "[OK] no script"
