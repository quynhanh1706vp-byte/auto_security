from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

# 1) Gỡ block INLINE ROUTE cũ (nếu có) để tránh đè route 2 lần
start_marker = "# --- INLINE ROUTE: /api/vsp/run_full_scan (no blueprint) ---"
end_marker   = "# --- END INLINE ROUTE ---"

if start_marker in txt and end_marker in txt:
    start = txt.index(start_marker)
    end = txt.index(end_marker, start) + len(end_marker)
    removed_block = txt[start:end]
    txt = txt[:start] + txt[end:]
    print("[INFO] Đã gỡ block INLINE ROUTE cũ /api/vsp/run_full_scan.")
else:
    print("[INFO] Không thấy block INLINE ROUTE cũ, bỏ qua bước gỡ.")

# 2) Thêm block auto-register mới vào cuối file
auto_block = r'''

# ===================== VSP RUN_FULL_SCAN AUTOREG V1 ==========================
from pathlib import Path as _Path_for_run_full_scan
import subprocess as _subprocess_for_run_full_scan
from flask import jsonify as _jsonify_for_run_full_scan, request as _request_for_run_full_scan
from flask import Flask as _Flask_for_run_full_scan

# ui/vsp_demo_app.py -> SECURITY_BUNDLE root
_ROOT_VSP = _Path_for_run_full_scan(__file__).resolve().parents[1]

def _vsp_run_full_scan_impl():
    """
    Impl chung cho /api/vsp/run_full_scan.
    Gọi bin/vsp_selfcheck_full ở ROOT_VSP để chạy full scan.
    """
    payload = _request_for_run_full_scan.get_json(silent=True) or {}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    script = _ROOT_VSP / "bin" / "vsp_selfcheck_full"

    if not script.is_file():
        return _jsonify_for_run_full_scan(
            ok=False,
            error=f"Script not found: {script}",
        ), 500

    try:
        proc = _subprocess_for_run_full_scan.Popen(
            [str(script)],
            cwd=str(_ROOT_VSP),
            stdout=_subprocess_for_run_full_scan.DEVNULL,
            stderr=_subprocess_for_run_full_scan.DEVNULL,
        )
    except Exception as e:
        return _jsonify_for_run_full_scan(
            ok=False,
            error=f"Failed to start scan: {e}",
        ), 500

    return _jsonify_for_run_full_scan(
        ok=True,
        message="FULL scan started",
        cmd=str(script),
        pid=proc.pid,
        profile=profile,
        source_root=source_root,
        target_url=target_url,
    )

def _vsp_register_run_full_scan_on_app(_app):
    """
    Đăng ký route /api/vsp/run_full_scan lên 1 Flask app bất kỳ.
    Tránh trùng bằng cách check url_map trước.
    """
    try:
        for rule in _app.url_map.iter_rules():
            if rule.rule == "/api/vsp/run_full_scan" and "POST" in rule.methods:
                print(f"[VSP_RUN_FULL_SCAN] Route đã tồn tại trên app {_app.name}, bỏ qua.")
                return
        _app.add_url_rule(
            "/api/vsp/run_full_scan",
            "api_run_full_scan",
            _vsp_run_full_scan_impl,
            methods=["POST"],
        )
        print(f"[VSP_RUN_FULL_SCAN] Registered /api/vsp/run_full_scan trên app {_app.name}")
    except Exception as e:
        print(f"[VSP_RUN_FULL_SCAN] Lỗi khi register trên app {_app.name}: {e}")

# Tự động tìm mọi Flask app trong module và gắn route
try:
    for _name, _obj in list(globals().items()):
        if isinstance(_obj, _Flask_for_run_full_scan):
            _vsp_register_run_full_scan_on_app(_obj)
except Exception as _e:
    print("[VSP_RUN_FULL_SCAN] Auto-register failed:", _e)
# ================== END VSP RUN_FULL_SCAN AUTOREG V1 =========================

'''

if "VSP RUN_FULL_SCAN AUTOREG V1" in txt:
    print("[INFO] Block AUTOREG đã tồn tại, không chèn thêm.")
else:
    txt = txt.rstrip() + auto_block
    print("[OK] Đã append block AUTOREG V1 vào cuối vsp_demo_app.py.")

if txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_run_full_autoreg_v1")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print(f"[OK] Backup -> {backup.name}, updated vsp_demo_app.py.")
else:
    print("[INFO] Không có thay đổi với vsp_demo_app.py.")
