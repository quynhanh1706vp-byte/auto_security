#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_p0_gate_dashmw_${TS}"
echo "[BACKUP] ${WSGI}.bak_p0_gate_dashmw_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK_START = "VSP_P2_DISABLE_KPI_V4_AND_FORCE_DASH_MW_V2"
if "VSP_P0_GATE_DASH_FORCE_EMPTY_BY_ENV_V1" in s:
    print("[OK] already patched: VSP_P0_GATE_DASH_FORCE_EMPTY_BY_ENV_V1")
    raise SystemExit(0)

# Find start+end marker style blocks
m_start = re.search(r'(?m)^\s*.*' + re.escape(MARK_START) + r'.*$', s)
if not m_start:
    raise SystemExit("[ERR] cannot find start marker: " + MARK_START)

# Try to find an end marker line after start (common pattern: "/<MARK>")
m_end = re.search(r'(?m)^\s*.*\/' + re.escape(MARK_START) + r'.*$', s[m_start.end():])
if not m_end:
    # fallback: find next big separator block start
    m_end2 = re.search(r'(?m)^\s*#\s*={8,}.*$', s[m_start.end():])
    if not m_end2:
        raise SystemExit("[ERR] cannot find end boundary for dash mw block")
    end_idx = m_start.end() + m_end2.start()
else:
    end_idx = m_start.end() + m_end.start()

block = s[m_start.start():end_idx]
lines = block.splitlines(True)

# Inject gating header and indent body after the marker line
out = []
out.append(lines[0])
out.append('# VSP_P0_GATE_DASH_FORCE_EMPTY_BY_ENV_V1\n')
out.append('import os as _os\n')
out.append('if _os.getenv("VSP_SAFE_DISABLE_KPI_V4","0") != "1":\n')
out.append('    print("[VSP_DASH_MW] bypass force-empty (commercial mode)")\n')
out.append('else:\n')
# indent the rest of the block (except first marker line) into the else:
for ln in lines[1:]:
    out.append('    ' + ln if ln.strip() else ln)

s2 = s[:m_start.start()] + "".join(out) + s[end_idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched: VSP_P0_GATE_DASH_FORCE_EMPTY_BY_ENV_V1")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "== VERIFY (expect non-empty once KPI is enabled) =="
curl -fsS http://127.0.0.1:8910/api/vsp/dash_kpis | head -c 300; echo
curl -fsS http://127.0.0.1:8910/api/vsp/dash_charts | head -c 300; echo
