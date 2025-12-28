#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need date
command -v systemctl >/dev/null 2>&1 || true

PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

echo "== [1] check current compile =="
if python3 -m py_compile "$PYF" >/dev/null 2>&1; then
  echo "[OK] current $PYF compiles => no restore needed"
  exit 0
fi
echo "[WARN] current $PYF does NOT compile; searching backups..."

# find newest compiling backup
GOOD=""
for f in $(ls -1t "${PYF}.bak_"* 2>/dev/null || true); do
  if python3 -m py_compile "$f" >/dev/null 2>&1; then
    GOOD="$f"
    break
  fi
done

if [ -z "$GOOD" ]; then
  echo "[ERR] cannot find any compiling backup of $PYF"
  ls -1 "${PYF}.bak_"* 2>/dev/null | head -n 20 || true
  exit 3
fi

TS="$(date +%Y%m%d_%H%M%S)"
BAD_SNAP="${PYF}.BROKEN_SNAPSHOT_${TS}"
cp -f "$PYF" "$BAD_SNAP"
echo "[SNAPSHOT] saved broken file => $BAD_SNAP"

cp -f "$GOOD" "$PYF"
echo "[RESTORE] $PYF <= $GOOD"

python3 -m py_compile "$PYF" >/dev/null 2>&1 && echo "[OK] restored $PYF compiles"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.6

echo "== [2] port 8910 =="
ss -ltnp | grep -E ':8910\b' || true

echo "== [3] smoke /vsp5 =="
curl -sS -I http://127.0.0.1:8910/vsp5 | sed -n '1,12p' || true
