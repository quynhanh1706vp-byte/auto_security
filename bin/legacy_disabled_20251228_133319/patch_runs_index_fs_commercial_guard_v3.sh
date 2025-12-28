#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_runsfs_guard_v3_${TS}"
echo "[BACKUP] $F.bak_runsfs_guard_v3_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

# 0) đảm bảo có jsonify ở import (an toàn)
if "from flask import" in txt and "jsonify" not in txt.split("from flask import",1)[1].split("\n",1)[0]:
    txt = re.sub(r"from flask import ([^\n]+)",
                 lambda m: ("from flask import " + (m.group(1).strip() + ", jsonify").replace(", ,", ", ")),
                 txt, count=1)

# 1) “Surgical fix” cho os-local nếu có block inject kiểu "import os, datetime" bên trong function
txt = re.sub(r"\bimport\s+os\s*,\s*datetime\b", "import os as _os, datetime", txt)
txt = txt.replace("os.path.", "_os.path.")
txt = txt.replace("os.environ.", "_os.environ.")

# 2) Wrap handler vsp_runs_index_v3_fs bằng JSON guard (không đổi indent thân hàm)
# Tìm def vsp_runs_index_v3_fs(): và bọc body bằng try/except; giữ nguyên body cũ.
m = re.search(r"^@app\.get\(\"/api/vsp/runs_index_v3_fs\"\)\s*\ndef\s+vsp_runs_index_v3_fs\(\)\s*:\s*\n", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find vsp_runs_index_v3_fs route/function")

start = m.end()

# lấy indent của dòng đầu tiên trong body
rest = txt[start:]
lines = rest.splitlines(True)
if not lines:
    raise SystemExit("[ERR] function body empty")

# tìm dòng code đầu tiên (không blank/comment) để lấy indent
body_indent = None
for ln in lines:
    if ln.strip() == "" or ln.lstrip().startswith("#"):
        continue
    body_indent = re.match(r"^(\s+)", ln).group(1)
    break
if body_indent is None:
    body_indent = "    "

# nếu đã có guard marker thì bỏ qua
if "VSP_RUNS_FS_JSON_GUARD_V3" in txt:
    print("[INFO] JSON guard V3 already present; skip")
else:
    # xác định phạm vi function: tới def kế tiếp ở cột 0 hoặc EOF
    # (đơn giản và an toàn cho file demo_app)
    tail = txt[start:]
    nxt = re.search(r"^\ndef\s+\w+\(", tail, flags=re.M)
    func_body = tail if not nxt else tail[:nxt.start()]
    after = "" if not nxt else tail[nxt.start():]

    func_lines = func_body.splitlines(True)

    # chuẩn hóa: bọc toàn bộ body cũ vào try:
    wrapped = []
    wrapped.append(f"{body_indent}# === VSP_RUNS_FS_JSON_GUARD_V3 ===\n")
    wrapped.append(f"{body_indent}try:\n")
    for ln in func_lines:
        # tăng indent thêm 4 spaces (hoặc tương đương) cho mọi dòng body
        if ln.strip() == "":
            wrapped.append(ln)
        else:
            wrapped.append(body_indent + "    " + ln.lstrip("\n"))
    wrapped.append(f"{body_indent}except Exception as e:\n")
    wrapped.append(f"{body_indent}    return jsonify({{'ok': False, 'error': str(e), 'items': [], 'kpi': {{'total_runs': 0, 'last_n': 0}}, 'source': 'fs'}}), 500\n")
    wrapped.append(f"{body_indent}# === END VSP_RUNS_FS_JSON_GUARD_V3 ===\n")

    txt = txt[:start] + "".join(wrapped) + after
    print("[OK] wrapped vsp_runs_index_v3_fs with JSON guard V3")

p.write_text(txt, encoding="utf-8")
print("[OK] wrote", p)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] runs_index_v3_fs commercial guard v3 applied"
