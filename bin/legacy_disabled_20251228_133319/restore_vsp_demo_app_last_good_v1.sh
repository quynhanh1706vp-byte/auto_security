#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"

# Tìm các backup
mapfile -t BKPS < <(ls -1 vsp_demo_app.py.bak_* 2>/dev/null | sort -r || true)
if [ "${#BKPS[@]}" -eq 0 ]; then
  echo "[ERR] Không có backup vsp_demo_app.py.bak_*"
  exit 2
fi

echo "[SCAN] backups=${#BKPS[@]}"

pick=""
for b in "${BKPS[@]}"; do
  # chỉ xét backup có endpoint runs_index_v3_fs
  if ! grep -q "runs_index_v3_fs" "$b" 2>/dev/null; then
    continue
  fi
  # test compile
  cp "$b" "$F"
  if python3 -m py_compile "$F" >/dev/null 2>&1; then
    pick="$b"
    break
  fi
done

if [ -z "$pick" ]; then
  echo "[ERR] Không tìm thấy backup nào vừa có runs_index_v3_fs vừa py_compile OK."
  echo "      Gợi ý: ls -1 vsp_demo_app.py.bak_* | tail -n 30"
  exit 3
fi

# restore lại đúng backup đã pick (đã cp ở trên nhưng làm rõ log)
cp "$pick" "$F"
echo "[RESTORE_OK] $F <= $pick"
python3 -m py_compile "$F" && echo "[OK] py_compile passed"
