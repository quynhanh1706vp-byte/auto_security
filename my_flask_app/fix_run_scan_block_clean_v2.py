from pathlib import Path
import re

p = Path("api_vsp_dashboard_v2.py")
text = p.read_text(encoding="utf-8")

# Tìm vị trí chứa câu "Trigger FULL EXT scan từ UI Settings"
marker = "Trigger FULL EXT scan từ UI Settings"
idx = text.find(marker)

if idx == -1:
    print("[ERR] Không tìm thấy marker trong file, không sửa được.")
    raise SystemExit(1)

# Tìm ngược lại tới decorator route tương ứng
route_start = text.rfind('@bp_vsp_dashboard_v2.route("/api/vsp/run_scan"', 0, idx)
if route_start == -1:
    # fallback: thử với '@bp.route'
    route_start = text.rfind('@bp.route("/api/vsp/run_scan"', 0, idx)

if route_start == -1:
    print("[ERR] Không tìm thấy decorator /api/vsp/run_scan trước marker.")
    raise SystemExit(1)

# Cắt phần trước block lỗi
head = text[:route_start]

backup = p.with_suffix(p.suffix + ".bak_fix_run_scan_block_clean_v2")
backup.write_text(text, encoding="utf-8")
print("[BACKUP] ->", backup)

# Hàm mới, cú pháp chuẩn
append_block = '''

@bp_vsp_dashboard_v2.route("/api/vsp/run_scan", methods=["POST"])
def api_vsp_run_scan():
    """Trigger FULL EXT scan từ UI Settings, gọi wrapper shell.

    Wrapper: bin/vsp_run_full_ext_from_settings_v1.sh
    """
    from flask import request, jsonify
    import os
    import subprocess
    import time
    from pathlib import Path

    data = request.get_json(silent=True) or {}
    src = data.get("src") or "/home/test/Data/SECURITY_BUNDLE"
    profile = data.get("profile") or "EXT+"

    ROOT = Path(__file__).resolve().parents[2]
    wrapper = ROOT / "bin" / "vsp_run_full_ext_from_settings_v1.sh"

    if not wrapper.is_file():
        return jsonify({
            "ok": False,
            "error": f"Wrapper not found: {wrapper}",
        }), 500

    env = os.environ.copy()
    env["VSP_SRC"] = src
    env["VSP_PROFILE"] = profile

    ts = time.strftime("%Y%m%d_%H%M%S")
    log_hint = f"out/vsp_run_from_settings.log ({ts})"

    try:
        proc = subprocess.Popen(
            ["bash", str(wrapper)],
            cwd=str(ROOT),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        return jsonify({
            "ok": False,
            "error": f"Failed to start wrapper: {e}",
        }), 500

    return jsonify({
        "ok": True,
        "message": "Scan started via wrapper.",
        "src": src,
        "profile": profile,
        "pid": proc.pid,
        "log_hint": log_hint,
    }), 200

'''

new_text = head.rstrip() + append_block + "\n"
p.write_text(new_text, encoding="utf-8")
print("[OK] Đã xoá block lỗi và ghi lại api_vsp_run_scan() sạch.")
