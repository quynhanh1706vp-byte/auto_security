#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Nếu đã patch rồi thì thôi
if "API_RUN_SCAN_V1" in text:
    print("[OK] Đã có block API_RUN_SCAN_V1, bỏ qua.")
    raise SystemExit(0)

chunk = """

# === API_RUN_SCAN_V1 ===
@app.route("/api/run_scan", methods=["POST"])
def api_run_scan():
    \"\"\"Trigger chạy bin/run_all_tools_v2.sh từ UI (chạy nền).\"\"\"
    import subprocess, json, os
    from flask import request, jsonify  # đảm bảo có import

    try:
        data = request.get_json(silent=True) or {}
    except Exception:
        data = {}

    src_folder = (data.get("src_folder") or "").strip()
    target_url = (data.get("target_url") or "").strip()

    if not src_folder:
        # fallback mặc định
        src_folder = "/home/test/Data/Khach"

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    cmd = ["bash", "bin/run_all_tools_v2.sh", src_folder]

    log_dir = os.path.join(root, "out")
    os.makedirs(log_dir, exist_ok=True)
    log_path = os.path.join(log_dir, "last_web_run.log")

    # Ghi log + spawn process nền
    with open(log_path, "ab", buffering=0) as f:
        f.write(("\\n\\n[WEB_RUN] start cmd=%r\\n" % (cmd,)).encode("utf-8", "replace"))
        subprocess.Popen(
            cmd,
            cwd=root,
            stdout=f,
            stderr=subprocess.STDOUT,
        )

    return jsonify({
        "status": "started",
        "src_folder": src_folder,
        "cmd": " ".join(cmd),
        "log_path": log_path,
        "target_url": target_url,
    })
"""

path.write_text(text + chunk, encoding="utf-8")
print("[OK] Đã append API_RUN_SCAN_V1 vào app.py.")
PY
