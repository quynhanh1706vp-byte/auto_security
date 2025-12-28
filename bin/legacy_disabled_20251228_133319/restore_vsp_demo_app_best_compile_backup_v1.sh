#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.broken_${TS}"
echo "[BACKUP] saved current broken -> $F.broken_${TS}"

# Collect backups newest-first
mapfile -t BKPS < <(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)
if [ "${#BKPS[@]}" -eq 0 ]; then
  echo "[ERR] no backups found: vsp_demo_app.py.bak_*"
  exit 1
fi

echo "[INFO] found ${#BKPS[@]} backups. scanning for first compile-ok + has runs_index_v3_fs ..."

pick=""
for b in "${BKPS[@]}"; do
  # must contain endpoint marker (avoid restoring too old file)
  if ! grep -q "runs_index_v3_fs" "$b"; then
    continue
  fi
  # compile check (no execution)
  if python3 - <<PY >/dev/null 2>&1
import pathlib
src = pathlib.Path("$b").read_text(encoding="utf-8", errors="ignore")
compile(src, "$b", "exec")
PY
  then
    pick="$b"
    break
  fi
done

if [ -z "$pick" ]; then
  echo "[ERR] cannot find any backup that compiles AND contains runs_index_v3_fs"
  echo "Tip: list latest 30 backups:"
  ls -1t vsp_demo_app.py.bak_* 2>/dev/null | head -n 30
  exit 2
fi

cp "$pick" "$F"
echo "[OK] restored vsp_demo_app.py from: $pick"

# final sanity compile
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK after restore"
