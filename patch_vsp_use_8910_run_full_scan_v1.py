from pathlib import Path
import re

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
p = ROOT / "vsp_demo_app.py"

txt = p.read_text(encoding="utf-8")
orig = txt

# 1) Đảm bảo có route /api/vsp/run_full_scan trên app
if "/api/vsp/run_full_scan" not in txt:
    route_block = r'''

# ===================== VSP RUN_FULL_SCAN INLINE (8910) ==========================
from pathlib import Path as _Path_for_run_full_scan_final
import subprocess as _subprocess_for_run_full_scan_final
from flask import jsonify as _jsonify_for_run_full_scan_final, request as _request_for_run_full_scan_final

_ROOT_VSP_FINAL = _Path_for_run_full_scan_final(__file__).resolve().parents[1]

@app.route("/api/vsp/run_full_scan", methods=["POST"])
def api_run_full_scan_final():
    """
    Trigger FULL scan từ UI gateway (port 8910).
    Gọi bin/vsp_selfcheck_full ở ROOT_VSP.
    """
    payload = _request_for_run_full_scan_final.get_json(silent=True) or {}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    script = _ROOT_VSP_FINAL / "bin" / "vsp_selfcheck_full"

    if not script.is_file():
        return _jsonify_for_run_full_scan_final(
            ok=False,
            error=f"Script not found: {script}",
        ), 500

    try:
        proc = _subprocess_for_run_full_scan_final.Popen(
            [str(script)],
            cwd=str(_ROOT_VSP_FINAL),
            stdout=_subprocess_for_run_full_scan_final.DEVNULL,
            stderr=_subprocess_for_run_full_scan_final.DEVNULL,
        )
    except Exception as e:
        return _jsonify_for_run_full_scan_final(
            ok=False,
            error=f"Failed to start scan: {e}",
        ), 500

    return _jsonify_for_run_full_scan_final(
        ok=True,
        message="FULL scan started",
        cmd=str(script),
        pid=proc.pid,
        profile=profile,
        source_root=source_root,
        target_url=target_url,
    )
# ================== END VSP RUN_FULL_SCAN INLINE (8910) =========================

'''
    txt = txt.rstrip() + route_block
    print("[OK] Đã append route /api/vsp/run_full_scan vào cuối vsp_demo_app.py")
else:
    print("[INFO] Đã có /api/vsp/run_full_scan trong file, không append thêm.")


# 2) Chuẩn hoá block __main__ để luôn chạy app trên port 8910
main_pat = re.compile(r'if __name__ == [\'"]__main__[\'"]:\s*([\s\S]*)$', re.MULTILINE)
m = main_pat.search(txt)

main_block = '''
if __name__ == "__main__":
    # UI gateway chạy ở port 8910
    app.run(host="0.0.0.0", port=8910, debug=True)
'''

if m:
    txt = txt[:m.start()] + main_block + "\n"
    print("[OK] Đã thay block __main__ bằng app.run(... port=8910)")
else:
    # nếu không có block __main__, thêm mới
    txt = txt.rstrip() + "\n\n" + main_block + "\n"
    print("[OK] Không thấy __main__, đã thêm block app.run(... port=8910) mới.")

if txt != orig:
    backup = p.with_suffix(p.suffix + ".bak_use_8910_run_full_scan_v1")
    backup.write_text(orig, encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print(f"[OK] Backup -> {backup.name}, updated vsp_demo_app.py")
else:
    print("[INFO] Không có thay đổi đối với vsp_demo_app.py")
