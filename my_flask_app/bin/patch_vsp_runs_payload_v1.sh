#!/bin/bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui/my_flask_app"
cd "$ROOT"

echo "[i] Patching VSP JS to use .runs từ /api/vsp/runs_v2..."

python3 - << 'PY'
from pathlib import Path

# Các file có thể dùng dữ liệu runs history
paths = [
    Path("static/js/vsp_dashboard_live_v2.js"),
    Path("static/js/vsp_runs_live_v1.js"),
    Path("static/js/vsp_tabs_runtime_v2.js"),
]

# Các pattern phổ biến kiểu data.items → đổi thành runs-based
repls = [
    ("data.items || []", "data.runs || data.items || []"),
    ("runsResp.items || []", "runsResp.runs || runsResp.items || []"),
    ("dataRuns.items || []", "dataRuns.runs || dataRuns.items || []"),
    ("payload.items || []", "payload.runs || payload.items || []"),
    ("(resp.items || [])", "(resp.runs || resp.items || [])"),
]

for path in paths:
    if not path.exists():
        print("[SKIP]", path, "không tồn tại")
        continue

    # backup 1 lần
    backup = path.with_suffix(path.suffix + ".bak_runs_payload_v1")
    if not backup.exists():
        backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
        print("[i] Backup ->", backup)

    txt = path.read_text(encoding="utf-8")
    before = txt
    count = 0

    for old, new in repls:
        if old in txt:
            txt = txt.replace(old, new)
            count += 1

    if txt != before:
        path.write_text(txt, encoding="utf-8")
        print("[OK]", path, "- thay", count, "pattern (.items -> .runs||.items)")
    else:
        print("[OK]", path, "- không cần sửa (.items không còn)")
PY

echo "[DONE] patch_vsp_runs_payload_v1.sh xong."
