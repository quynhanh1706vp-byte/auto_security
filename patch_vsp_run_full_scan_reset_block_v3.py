from pathlib import Path

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

start_marker = "# ===================== VSP RUN_FULL_SCAN INLINE V3 =========================="
end_marker   = "# ================== END VSP RUN_FULL_SCAN INLINE V3 ========================="

start_idx = txt.find(start_marker)
end_idx = txt.find(end_marker)

block = f"""{start_marker}
from pathlib import Path as _Path_for_run_full_scan_v3
import subprocess as _subprocess_for_run_full_scan_v3
from flask import jsonify as _jsonify_for_run_full_scan_v3, request as _request_for_run_full_scan_v3

# ui/vsp_demo_app.py -> SECURITY_BUNDLE ROOT
_ROOT_VSP_V3 = _Path_for_run_full_scan_v3(__file__).resolve().parents[1]

def api_run_full_scan_v3():
    \"\"\"Trigger FULL scan từ UI gateway (port 8910).

    Gọi script trong bin/ ở ROOT_VSP (tự động chọn tên tồn tại).
    \"\"\"
    payload = _request_for_run_full_scan_v3.get_json(silent=True) or {{}}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    # Tự chọn script thật trong bin/
    candidates = [
        "vsp_selfcheck_full",
        "vsp_selfcheck_full.sh",
        "vsp_run_full_ext_v1.sh",
        "vsp_run_full_ext.sh",
    ]

    script = None
    for name in candidates:
        candidate_path = _ROOT_VSP_V3 / "bin" / name
        if candidate_path.is_file():
            script = candidate_path
            break

    if script is None:
        return _jsonify_for_run_full_scan_v3(
            ok=False,
            error="No run script found in bin/. Tried: " + ", ".join(candidates),
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
            error=f"Failed to start scan: {{e}}",
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

# Đăng ký route lên app
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

{end_marker}
"""

if start_idx != -1 and end_idx != -1:
    # cắt từ đầu tới start_marker, rồi nhét block mới, rồi phần sau end_marker
    end_idx_line_end = txt.find("\n", end_idx)
    if end_idx_line_end == -1:
        end_idx_line_end = len(txt)
    new_txt = txt[:start_idx] + block + txt[end_idx_line_end:]
    print("[OK] Đã thay thế block V3 cũ bằng block mới.")
else:
    # nếu chưa có marker, append block mới vào cuối file
    new_txt = txt.rstrip() + "\n\n" + block + "\n"
    print("[OK] Không thấy block V3 cũ, đã append block mới vào cuối file.")

if new_txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_run_full_reset_v3")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(new_txt, encoding="utf-8")
    print(f"[OK] Backup -> {backup.name}, updated vsp_demo_app.py")
else:
    print("[INFO] Không có thay đổi với vsp_demo_app.py")
