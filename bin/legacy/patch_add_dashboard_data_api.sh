#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, textwrap, pathlib

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

# Nếu đã có /api/dashboard_data thì thôi
if "/api/dashboard_data" in data:
    print("[OK] app.py đã có route /api/dashboard_data, bỏ qua.")
    raise SystemExit(0)

block = """
@app.route("/api/dashboard_data")
def api_dashboard_data():
    \"\"\"Trả về JSON summary_unified cho Dashboard (dùng cho front-end fetch).\"\"\"
    import json, os
    from pathlib import Path

    ROOT = Path(__file__).resolve().parent.parent
    out_dir = ROOT / "out"

    if not out_dir.is_dir():
        return {"error": f"Not found: {out_dir}"}, 404

    latest_run = None
    for name in sorted(os.listdir(out_dir)):
        if name.startswith("RUN_"):
            latest_run = name
    if not latest_run:
        return {"error": "No RUN_* found in out/"}, 404

    summary_path = out_dir / latest_run / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return {"error": f"Not found: {summary_path}"}, 404

    with summary_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    return data
"""

if "if __name__ == \"__main__\":" in data:
    new_data = data.replace(
        "if __name__ == \"__main__\":",
        textwrap.dedent(block) + "\n\nif __name__ == \"__main__\":",
        1,
    )
else:
    new_data = data + textwrap.dedent(block)

path.write_text(new_data, encoding="utf-8")
print("[OK] Đã thêm route /api/dashboard_data vào app.py")
PY
