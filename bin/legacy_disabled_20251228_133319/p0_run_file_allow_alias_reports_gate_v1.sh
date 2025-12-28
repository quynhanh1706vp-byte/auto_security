#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_alias_${TS}"
echo "[BACKUP] ${W}.bak_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_ALIAS_REPORTS_GATE_V1"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

# Find the run_file_allow handler block (best-effort) and inject after the line that reads query param 'path'
# We search for a window around the first occurrence of "run_file_allow" and then locate path assignment.
pos = s.find("run_file_allow")
if pos == -1:
    raise SystemExit("[ERR] cannot find 'run_file_allow' in WSGI")

win_start = max(0, pos - 2000)
win_end   = min(len(s), pos + 12000)
win = s[win_start:win_end]

m = re.search(r"(?m)^\s*path\s*=\s*.*request\.args\.get\(\s*['\"]path['\"]", win)
if not m:
    # fallback: any request.args.get('path')
    m = re.search(r"request\.args\.get\(\s*['\"]path['\"]", win)
    if not m:
        raise SystemExit("[ERR] cannot locate request.args.get('path') near run_file_allow")

# inject right after the line containing path=... if possible
line_start = win.rfind("\n", 0, m.start())
line_end   = win.find("\n", m.start())
if line_start == -1: line_start = 0
if line_end == -1: line_end = len(win)

inject = """
  # ===================== VSP_P0_ALIAS_REPORTS_GATE_V1 =====================
  # If UI requests reports/run_gate*.json but run artifacts store them at root,
  # rewrite to root to avoid 403 and keep commercial UX clean.
  try:
    _p0 = (path or "").replace("\\\\","/").lstrip("/")
    if _p0 in ("reports/run_gate_summary.json", "reports/run_gate.json"):
      path = _p0.split("/", 1)[1]  # drop leading "reports/"
  except Exception:
    pass
  # ===================== /VSP_P0_ALIAS_REPORTS_GATE_V1 =====================
"""

patched_win = win[:line_end+1] + inject + win[line_end+1:]
s2 = s[:win_start] + patched_win + s[win_end:]

p.write_text(s2, encoding="utf-8")
print("[OK] injected alias block:", MARK)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6
echo "[OK] restarted (or attempted)"
