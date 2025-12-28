#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl missing"; exit 2; }

FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)

echo "== [0] initial status =="
systemctl status "$SVC" --no-pager -l || true

echo "== [1] restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [2] wait readiness (max 10s) =="
UP=0
for i in $(seq 1 10); do
  if curl -fsS -o /dev/null --connect-timeout 2 "$BASE/runs"; then UP=1; break; fi
  sleep 1
done
if [ "$UP" -eq 1 ]; then
  echo "[OK] service is up"
  exit 0
fi

echo "[WARN] still down -> check compile + auto-restore latest good backups"

python3 - <<'PY'
from pathlib import Path
import py_compile, re

FILES = ["vsp_demo_app.py", "wsgi_vsp_ui_gateway.py"]

def compiles(fp: Path) -> bool:
    try:
        py_compile.compile(str(fp), doraise=True)
        return True
    except Exception:
        return False

def pick_latest_good_backup(orig: Path) -> Path | None:
    # common backup patterns: <file>.bak_*_<TS> or .bak_* etc
    baks = sorted(orig.parent.glob(orig.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    for b in baks:
        if compiles(b):
            return b
    return None

for fn in FILES:
    p = Path(fn)
    if not p.exists():
        print(f"[SKIP] missing {fn}")
        continue

    ok = compiles(p)
    print(f"[CHECK] {fn} compile_ok={ok}")
    if ok:
        continue

    good = pick_latest_good_backup(p)
    if not good:
        raise SystemExit(f"[ERR] {fn} is broken and no compiling backup found")

    snap = p.with_suffix(p.suffix + f".bak_broken_snapshot_{__import__('time').strftime('%Y%m%d_%H%M%S')}")
    snap.write_bytes(p.read_bytes())
    p.write_bytes(good.read_bytes())
    print(f"[RESTORE] {fn} <= {good.name} (snapshot: {snap.name})")

print("[OK] restore done (if needed)")
PY

echo "== [3] restart after restore =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [4] tail logs (last 80) =="
journalctl -u "$SVC" -n 80 --no-pager || true

echo "== [5] final readiness (max 20s) =="
UP=0
for i in $(seq 1 20); do
  if curl -fsS -o /dev/null --connect-timeout 2 "$BASE/runs"; then UP=1; break; fi
  sleep 1
done

if [ "$UP" -eq 1 ]; then
  echo "[OK] revived: /runs reachable"
  exit 0
fi

echo "[FAIL] still not reachable: $BASE/runs"
exit 1
