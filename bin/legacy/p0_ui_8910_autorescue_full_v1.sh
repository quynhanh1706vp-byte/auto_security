#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl
command -v systemctl >/dev/null 2>&1 || { echo "[ERR] systemctl missing"; exit 2; }

APP="vsp_demo_app.py"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

snap(){
  local f="$1"
  cp -f "$f" "${f}.bak_autorescue_full_${TS}"
  echo "[SNAPSHOT] ${f}.bak_autorescue_full_${TS}"
}

best_compile_backup(){
  local f="$1"
  python3 - <<PY
from pathlib import Path
import py_compile, sys

f = Path("$f")
baks = sorted(Path(".").glob(f.name + ".bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
best = None
for p in baks:
    try:
        py_compile.compile(str(p), doraise=True)
        best = p
        break
    except Exception:
        continue
print(str(best) if best else "")
PY
}

restore_if_needed(){
  local f="$1"
  echo "== compile check: $f =="
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    echo "[OK] $f compiles"
    return 0
  fi
  echo "[WARN] $f compile FAIL -> searching backups"
  local best
  best="$(best_compile_backup "$f")"
  if [ -z "${best:-}" ]; then
    echo "[ERR] no compiling backup found for $f"
    return 2
  fi
  echo "[RESTORE] $best -> $f"
  cp -f "$best" "$f"
  python3 -m py_compile "$f"
  echo "[OK] restored compiling $f"
}

echo "== [0] snapshot current files =="
snap "$APP"
snap "$WSGI"

echo "== [1] stop service hard =="
systemctl stop "$SVC" 2>/dev/null || true

echo "== [2] kill listeners on :8910 (just in case) =="
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*:8910 .*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS 2>/dev/null || true

echo "== [3] restore compile-ok for APP + WSGI =="
restore_if_needed "$APP"
restore_if_needed "$WSGI"

echo "== [4] quick import test =="
python3 - <<'PY'
import importlib
m = importlib.import_module("wsgi_vsp_ui_gateway")
print("[OK] import wsgi_vsp_ui_gateway")
print("has application=", hasattr(m, "application"), "has app=", hasattr(m, "app"))
PY

echo "== [5] restart service =="
systemctl restart "$SVC"

echo "== [6] wait up to 6s for healthz =="
ok=0
for i in 1 2 3 4 5 6; do
  if curl -fsS "$BASE/api/vsp/healthz" >/dev/null 2>&1; then ok=1; break; fi
  sleep 1
done

echo "== [7] result =="
ss -ltnp | grep ':8910' || echo "NO LISTENER"
if [ "$ok" = "1" ]; then
  curl -fsS "$BASE/api/vsp/healthz" | python3 -m json.tool | head -n 60
  echo "[DONE] UP: $BASE"
else
  echo "[FAIL] healthz still not reachable"
  systemctl status "$SVC" --no-pager -l || true
  journalctl -u "$SVC" -n 120 --no-pager || true
  exit 2
fi
