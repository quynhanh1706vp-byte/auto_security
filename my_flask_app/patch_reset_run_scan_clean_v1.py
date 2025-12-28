from pathlib import Path
import re

p = Path("api_vsp_dashboard_v2.py")
text = p.read_text(encoding="utf-8")

# 1) XÓA TẤT CẢ các block route + def liên quan /api/vsp/run_scan
pattern = r'@bp[_\w]*\.route\("/api/vsp/run_scan"[\s\S]+?def api_vsp_run_scan[_\w]*\([\s\S]+?(?=\n@|\Z)'
new_text, n = re.subn(pattern, '', text, flags=re.MULTILINE)

print(f"[INFO] Đã xoá {n} block /api/vsp/run_scan cũ")

backup = p.with_suffix(p.suffix + ".bak_reset_run_scan_clean_v1")
backup.write_text(text, encoding="utf-8")
print("[BACKUP] ->", backup)

text = new_text.rstrip() + "\n\n"

# 2) THÊM LẠI 1 HÀM DUY NHẤT, SẠCH
append_block = r"""

@bp_vsp_dashboard_v2.route("/api/vsp/run_scan", methods=["POST"])
def api_vsp_run_scan():
    \"\"\"Trigger FULL EXT scan từ UI Settings, gọi wrapper shell.

    Wrapper: bin/vsp_run_full_ext_from_settings_v1.sh
    \"\"\"
    from flask import request, jsonify
    import os
    import subprocess
    from pathlib import Path
    import time

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
"""

text = text + append_block + "\n"
p.write_text(text, encoding="utf-8")
print("[DONE] Đã ghi lại 1 hàm duy nhất api_vsp_run_scan()")
