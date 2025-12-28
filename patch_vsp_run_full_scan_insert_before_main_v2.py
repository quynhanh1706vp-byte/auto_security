from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

# 0) Gỡ mọi dòng cũ có chữ run_full_scan để khỏi trùng
new_txt, n = re.subn(r'.*run_full_scan.*\n', '', txt)
if n:
    print(f"[INFO] Đã xoá {n} dòng cũ chứa 'run_full_scan'")
txt = new_txt

# 1) Tìm vị trí block __main__
marker = 'if __name__ == "__main__":'
idx = txt.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy 'if __name__ == \"__main__\":' trong vsp_demo_app.py")
    quit(1)

# 2) Chuẩn bị block route chèn TRƯỚC __main__
block = r'''

# ===================== VSP RUN_FULL_SCAN INLINE V3 ==========================
from pathlib import Path as _Path_for_run_full_scan_v3
import subprocess as _subprocess_for_run_full_scan_v3
from flask import jsonify as _jsonify_for_run_full_scan_v3, request as _request_for_run_full_scan_v3

# ui/vsp_demo_app.py -> SECURITY_BUNDLE ROOT
_ROOT_VSP_V3 = _Path_for_run_full_scan_v3(__file__).resolve().parents[1]

def api_run_full_scan_v3():
    """
    Trigger FULL scan từ UI gateway (port 8910).
    Gọi bin/vsp_selfcheck_full ở ROOT_VSP.
    """
    payload = _request_for_run_full_scan_v3.get_json(silent=True) or {}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    script = _ROOT_VSP_V3 / "bin" / "vsp_selfcheck_full"

    if not script.is_file():
        return _jsonify_for_run_full_scan_v3(
            ok=False,
            error=f"Script not found: {script}",
        ), 500

    try:
        proc = _subprocess_for_run_full_scan_v3.Popen(
            [str(script)],
            cwd=str(_ROOT_VSP_V3),
            stdout=_subprocess_for_run_full_scan_v3.DEVNULL,
            stderr=_subprocess_for_run_full_scan_v3.DEVNULL,
        )
    except Exception as e:
        return _jsonify_for_run_full_scan_v3(
            ok=False,
            error=f"Failed to start scan: {e}",
        ), 500

    return _jsonify_for_run_full_scan_v3(
        ok=True,
        message="FULL scan started",
        cmd=str(script),
        pid=proc.pid,
        profile=profile,
        source_root=source_root,
        target_url=target_url,
    )

# Đăng ký route lên app bằng add_url_rule
try:
    _app_v3 = app
    exists = any(rule.rule == "/api/vsp/run_full_scan" for rule in _app_v3.url_map.iter_rules())
    if not exists:
        _app_v3.add_url_rule(
            "/api/vsp/run_full_scan",
            "api_run_full_scan_v3",
            api_run_full_scan_v3,
            methods=["POST"],
        )
        print("[VSP_RUN_FULL_SCAN_V3] Registered /api/vsp/run_full_scan trên app", _app_v3.name)
    else:
        print("[VSP_RUN_FULL_SCAN_V3] Route /api/vsp/run_full_scan đã tồn tại, bỏ qua.")
except Exception as _e:
    print("[VSP_RUN_FULL_SCAN_V3] Lỗi khi register route:", _e)
# ================== END VSP RUN_FULL_SCAN INLINE V3 =========================

'''

txt = txt[:idx] + block + "\n" + txt[idx:]

if txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_run_full_v3_before_main")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print(f"[OK] Đã chèn block V3, backup -> {backup.name}")
else:
    print("[INFO] Không có thay đổi với vsp_demo_app.py")
