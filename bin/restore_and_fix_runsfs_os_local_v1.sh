#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"

pick_latest() {
  ls -1 "$1" 2>/dev/null | sort | tail -n 1 || true
}

# ƯU TIÊN restore từ backup "bak_runsfs_sort_*" (đã từng chạy OK)
BKP="$(pick_latest "vsp_demo_app.py.bak_runsfs_sort_*")"
if [ -z "$BKP" ]; then
  echo "[ERR] Không tìm thấy backup kiểu vsp_demo_app.py.bak_runsfs_sort_*"
  echo "      Hãy ls -1 vsp_demo_app.py.bak_* | tail -n 20 và chọn cái chạy OK."
  exit 2
fi

cp "$BKP" "$F"
echo "[RESTORE] $F <= $BKP"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# Fix UnboundLocalError: os bị local do 'import os' trong block inject
# => đổi 'import os, datetime' -> 'import os as _os, datetime' và thay toàn bộ os.path -> _os.path trong block.
def patch_block(marker):
    nonlocal_txt = None

def do_patch(txt):
    # tìm block SORT V1 hoặc V2 (nếu có)
    for ver in ("V1", "V2"):
        start = f"# === VSP_COMMERCIAL_RUNS_FS_SORT_{ver} ==="
        end   = f"# === END VSP_COMMERCIAL_RUNS_FS_SORT_{ver} ==="
        if start in txt and end in txt:
            a = txt.index(start)
            b = txt.index(end) + len(end)
            blk = txt[a:b]
            blk2 = blk

            # 1) tránh tạo local name 'os'
            blk2 = re.sub(r"\bimport\s+os\s*,\s*datetime\b", "import os as _os, datetime", blk2)
            blk2 = re.sub(r"\bimport\s+os\s+as\s+_os\s*,\s*datetime\b", "import os as _os, datetime", blk2)

            # 2) thay os.path.* -> _os.path.*
            blk2 = blk2.replace("os.path.", "_os.path.")
            blk2 = blk2.replace("os.environ.", "_os.environ.")  # phòng khi có
            # 3) nếu có os.path.join(...) trong OUT_DIR compute
            blk2 = blk2.replace("os.path.join", "_os.path.join")

            if blk2 != blk:
                txt = txt[:a] + blk2 + txt[b:]
                print(f"[OK] Patched SORT block {ver}: avoid local 'os' (use _os)")
            else:
                print(f"[INFO] SORT block {ver} present but no changes needed")
            return txt
    print("[WARN] No SORT block markers found; nothing patched")
    return txt

txt2 = do_patch(txt)
p.write_text(txt2, encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] restore + fix os-local in runs_index_v3_fs"
