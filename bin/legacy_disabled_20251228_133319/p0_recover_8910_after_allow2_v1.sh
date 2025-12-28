#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ss; need awk; need sed; need grep; need tail

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_recover_8910_${TS}"
echo "[BACKUP] ${W}.bak_recover_8910_${TS}"

echo "== [1] quick patch: ensure allow2 block imports Path (safe) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P2_RUN_FILE_ALLOW2_NO403_V1"
if marker not in s:
    print("[INFO] allow2 marker not found, skip")
    raise SystemExit(0)

# If allow2 block uses Path(...) but no import, add it near the allow2 helpers.
if "from pathlib import Path" not in s:
    # insert just after the allow2 marker line
    s2, n = re.subn(rf"(^\s*#\s*====================\s*{re.escape(marker)}\s*====================\s*$)",
                    r"\1\nfrom pathlib import Path  # auto-added (recover_8910)\n",
                    s, flags=re.M)
    if n:
        p.write_text(s2, encoding="utf-8")
        print("[OK] inserted 'from pathlib import Path' near allow2 marker")
    else:
        print("[WARN] could not insert Path import automatically")
else:
    print("[OK] Path import already present")
PY

echo "== [2] import sanity (this catches runtime import errors that py_compile won't) =="
python3 - <<'PY' || true
import importlib.util, traceback
spec = importlib.util.spec_from_file_location("wsgi_vsp_ui_gateway", "wsgi_vsp_ui_gateway.py")
m = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(m)
    # app may be named app/application depending on your gateway
    a = getattr(m, "app", None) or getattr(m, "application", None)
    print("[OK] import OK; app=", type(a))
except Exception as e:
    print("[ERR] import failed:", e)
    traceback.print_exc()
PY

echo "== [3] cleanup port/lock (common cause: restart race / stale listener) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true

PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910|:8000/ {print}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
if [ -n "${PIDS// }" ]; then
  echo "[INFO] killing listeners: $PIDS"
  kill -9 $PIDS 2>/dev/null || true
fi

echo "== [4] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1.0

echo "== [5] status + listen check =="
systemctl --no-pager -l status "$SVC" | sed -n '1,80p' || true
ss -ltnp | egrep '(:8910|:8000)' || true

echo "== [6] quick HTTP sanity =="
curl -sS -I "$BASE/" | sed -n '1,12p' || true
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 260; echo || true

echo "== [7] if still down: show last journal lines (root cause) =="
journalctl -u "$SVC" -n 220 --no-pager | tail -n 220 || true
