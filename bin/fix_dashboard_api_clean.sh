#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
from pathlib import Path
import os, json

path = Path("app.py")
data = path.read_text(encoding="utf-8")
lines = data.splitlines(keepends=True)

out_lines = []
i = 0
removed = 0

while i < len(lines):
    line = lines[i]

    # Bỏ luôn các dòng rác chỉ chứa "\n"
    if line.strip() == r'\n':
        i += 1
        continue

    # Nếu gặp hàm api_dashboard_data -> xoá cả hàm + decorator ngay phía trên
    if 'def api_dashboard_data' in line:
        removed += 1
        # nếu dòng ngay trước là decorator /api/dashboard_data thì xoá luôn
        if out_lines and '"/api/dashboard_data"' in out_lines[-1]:
            out_lines.pop()

        # bỏ qua bản thân dòng def + toàn bộ body (các dòng thụt lề hoặc trống)
        i += 1
        while i < len(lines):
            l2 = lines[i]
            if l2.strip() == "" or l2.startswith(" ") or l2.startswith("\t"):
                i += 1
                continue
            else:
                break
        continue

    out_lines.append(line)
    i += 1

print(f"[INFO] Đã xoá {removed} định nghĩa api_dashboard_data cũ và các dòng rác '\\n'.")

cleaned = "".join(out_lines)

new_block = '''@app.route("/api/dashboard_data", methods=["GET"])
def api_dashboard_data():
    """
    Trả về JSON phẳng cho Dashboard.
    Lấy y nguyên nội dung summary_unified.json của RUN_* mới nhất
    (có thêm field 'run' để biết đang dùng RUN nào).
    """
    import json, os
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

    default = {
        "run": None,
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
    }

    if not out_dir.is_dir():
        return default

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_2"):  # chỉ lấy RUN_YYYYmmdd_...
            latest_run = name

    if not latest_run:
        return default

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return default

    try:
        with summary_path.open("r", encoding="utf-8") as f:
            summary = json.load(f)
    except Exception:
        return default

    summary.setdefault("total", 0)
    summary.setdefault("critical", summary.get("crit", 0))
    summary.setdefault("high", 0)
    summary.setdefault("medium", 0)
    summary.setdefault("low", 0)
    summary.setdefault("info", 0)
    summary["run"] = latest_run

    return summary
'''

# Append block mới ở CUỐI file, dùng newline thật
cleaned = cleaned.rstrip() + "\n\n" + new_block + "\n"
path.write_text(cleaned, encoding="utf-8")
print("[OK] Đã ghi lại app.py với đúng 1 route /api/dashboard_data.")
PY
