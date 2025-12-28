#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need cp
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] need systemctl"; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "[ERR] need curl"; exit 2; }

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "[BACKUP] current -> ${W}.bak_emergency_${TS}"
cp -f "$W" "${W}.bak_emergency_${TS}"

echo "== [1] Find latest compilable backup =="
python3 - <<'PY'
from pathlib import Path
import py_compile, sys

W=Path("wsgi_vsp_ui_gateway.py")

def ok(p: Path)->bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# if current ok, no need restore
if ok(W):
    print("[OK] current compiles, no restore needed")
    sys.exit(0)

baks=sorted(W.parent.glob(W.name+".bak_*"), key=lambda p:p.stat().st_mtime, reverse=True)
for b in baks[:120]:
    if ok(b):
        print("[RESTORE]", b.name)
        W.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(W), doraise=True)
        print("[OK] restored + compiles")
        sys.exit(0)

print("[ERR] no compilable backup found in last 120 backups")
sys.exit(2)
PY

echo "== [2] daemon-reload + restart service =="
sudo systemctl daemon-reload 2>/dev/null || systemctl daemon-reload || true
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC"

echo "== [3] wait port 8910 =="
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/healthz" >/dev/null 2>&1; then
    echo "[OK] UI up: $BASE"
    break
  fi
  sleep 0.2
done

echo "== [4] quick smoke (best-effort) =="
curl -fsS "$BASE/c/dashboard" >/dev/null && echo "[OK] /c/dashboard" || echo "[WARN] /c/dashboard fail"
curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" >/dev/null && echo "[OK] runs api" || echo "[WARN] runs api fail"

echo "[DONE] Gateway rescued."
