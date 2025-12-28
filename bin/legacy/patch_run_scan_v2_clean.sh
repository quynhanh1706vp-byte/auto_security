#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, re, os, textwrap

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = f.read()

original = data

# 1) XÓA TẤT CẢ BLOCK @app.route("/api/run_scan"... def api_run_scan(...)
pattern = r'@app\.route\("/api/run_scan"[^)]*\)\s*\ndef\s+api_run_scan\([^)]*\):'
matches = list(re.finditer(pattern, data))
if matches:
    print(f"[INFO] Tìm thấy {len(matches)} block api_run_scan cũ – sẽ xoá hết.")
    def cut_block(s, start_idx):
        # cắt từ @app.route("/api/run_scan"... đến ngay trước route kế tiếp hoặc EOF
        m = re.compile(r'^@app\.route\(', re.MULTILINE).search(s, start_idx + 1)
        end = m.start() if m else len(s)
        return s[:start_idx] + s[end:]
    for m in reversed(matches):
        data = cut_block(data, m.start())
else:
    print("[INFO] Không thấy block api_run_scan cũ nào, bỏ qua bước xoá.")

# 2) ĐẢM BẢO CÓ BLOCK /api/run_scan_v2
if '/api/run_scan_v2' in data:
    print("[INFO] Đã có route /api/run_scan_v2 trong app.py, không append thêm.")
else:
    print("[INFO] Chưa có route /api/run_scan_v2 – sẽ append block v2 ở cuối file.")
    block = textwrap.dedent('''
    # =====================================================================
    # API RUN SCAN V2 – gọi bin/run_all_tools_v2.sh từ Dashboard
    # =====================================================================
    @app.route("/api/run_scan_v2", methods=["POST"])
    def api_run_scan_v2():
        """
        Trigger SECURITY_BUNDLE scan từ UI Dashboard.
        Gọi: bin/run_all_tools_v2.sh "<SRC_FOLDER>"
        Sau khi xong sẽ đọc RUN_* mới nhất + summary_unified.json để trả về.
        """
        import os, re, json, subprocess
        from flask import request, jsonify

        data = request.get_json(silent=True) or {}

        src_folder = (data.get("src_folder") or "/home/test/Data/Khach").strip()
        target_url = (data.get("target_url") or "").strip()
        profile    = (data.get("profile") or "").strip()
        mode       = (data.get("mode") or "").strip()

        root = "/home/test/Data/SECURITY_BUNDLE"
        out_dir = os.path.join(root, "out")

        if not src_folder:
            src_folder = "/home/test/Data/Khach"

        cmd = [
            "bash", "-lc",
            f'cd "{root}" && bin/run_all_tools_v2.sh "{src_folder}"'
        ]

        print("[API][RUN_SCAN_V2] CMD:", " ".join(cmd), flush=True)
        rc = subprocess.call(cmd)
        print("[API][RUN_SCAN_V2] DONE rc =", rc, flush=True)

        # Tìm RUN_* mới nhất sau khi quét
        last_run = None
        if os.path.isdir(out_dir):
            run_dirs = sorted(
                [
                    d for d in os.listdir(out_dir)
                    if re.match(r"^RUN_[0-9]{8}_[0-9]{6}$", d)
                ],
                reverse=True,
            )
            if run_dirs:
                last_run = run_dirs[0]

        summary = {}
        if last_run:
            summary_path = os.path.join(out_dir, last_run, "report", "summary_unified.json")
            try:
                with open(summary_path, "r", encoding="utf-8") as f:
                    summary = json.load(f)
            except Exception as e:
                print("[API][RUN_SCAN_V2] WARN: không đọc được summary_unified.json:", e, flush=True)

        return jsonify({
            "ok": (rc == 0),
            "rc": int(rc),
            "last_run_id": last_run,
            "summary": summary,
            "src_folder": src_folder,
            "target_url": target_url,
            "profile": profile,
            "mode": mode,
        })
    ''')
    # đảm bảo file kết thúc bằng newline rồi mới append
    if not data.endswith("\n"):
        data += "\n"
    data += block

if data != original:
    with open(path, "w", encoding="utf-8") as f:
        f.write(data)
    print("[OK] Đã patch app.py (clean api_run_scan cũ + ensure api_run_scan_v2).")
else:
    print("[INFO] app.py không thay đổi.")
PY
