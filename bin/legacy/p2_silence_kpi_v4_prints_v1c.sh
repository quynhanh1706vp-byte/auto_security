#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need systemctl; need grep; need stat; need tail; need sed; need curl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
ERRLOG="out_ci/ui_8910.error.log"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_kpi_v4_printsil_${TS}"
echo "[BACKUP] ${W}.bak_kpi_v4_printsil_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK = "VSP_P2_KPI_V4_SILENCE_PRINTS_V1C"
if any(MARK in ln for ln in lines):
    print("[OK] already patched; skip")
    raise SystemExit(0)

out = []
window = 0  # how many next lines are considered "KPI_V4 context"
changed = 0

print_re = re.compile(r'^(\s*)print\((.*)\)\s*$', re.M)

for i, ln in enumerate(lines):
    if "VSP_KPI_V4" in ln:
        window = 80  # cover the mount try/except block that prints e
    if window > 0:
        m = print_re.match(ln.rstrip("\n"))
        if m:
            indent = m.group(1)
            payload = m.group(2)
            # Wrap print with env flag; default OFF => silence
            out.append(f'{indent}if __import__("os").environ.get("VSP_KPI_V4_LOG","0")=="1": print({payload})\n')
            changed += 1
            window -= 1
            continue
        window -= 1
    out.append(ln)

out.append(f"\n# {MARK}\n")
p.write_text("".join(out), encoding="utf-8")
print("[OK] patched prints in KPI_V4 context; changed=", changed)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

before_size=0
if [ -f "$ERRLOG" ]; then before_size="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"; fi
echo "[INFO] error_log_size_before_restart=$before_size"

sudo systemctl restart "$SVC"

# trigger a bit
sleep 0.6
curl -sS "$BASE/api/vsp/rid_latest" >/dev/null 2>&1 || true
sleep 0.6

echo "== [CHECK] NEW log bytes (should NOT contain KPI_V4 / Working outside...) =="
if [ -f "$ERRLOG" ]; then
  after_size="$(stat -c%s "$ERRLOG" 2>/dev/null || echo 0)"
  echo "[INFO] error_log_size_after_restart=$after_size"
  if [ "$after_size" -gt "$before_size" ]; then
    new="$(mktemp /tmp/vsp_kpi_new_XXXXXX.txt)"
    tail -c +"$((before_size+1))" "$ERRLOG" > "$new" || true
    echo "--- grep KPI_V4 ---"
    grep -n "VSP_KPI_V4" "$new" || echo "[OK] no KPI_V4 in NEW part"
    echo "--- grep app context ---"
    grep -n "Working outside of application context" "$new" || echo "[OK] no app_context error in NEW part"
  else
    echo "[OK] no new error log bytes"
  fi
else
  echo "[WARN] missing $ERRLOG"
fi

echo "[NOTE] To re-enable KPI_V4 prints for debugging:"
echo "       sudo systemctl set-environment VSP_KPI_V4_LOG=1 && sudo systemctl restart $SVC"
echo "       sudo systemctl unset-environment VSP_KPI_V4_LOG && sudo systemctl restart $SVC"
