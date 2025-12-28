from pathlib import Path
import re

p = Path("api_vsp_dashboard_v2.py")
text = p.read_text(encoding="utf-8")

# Xóa hoàn toàn tất cả function api_vsp_run_scan cũ
text = re.sub(
    r"@bp\.route\(\"/api/vsp/run_scan\"[\s\S]+?def api_vsp_run_scan[^\n]*\([\s\S]+?return jsonify\([^\n]+\)",
    "",
    text,
    flags=re.MULTILINE,
)

# Thêm function mới
append_block = """

@bp.route("/api/vsp/run_scan", methods=["POST"])
def api_vsp_run_scan():
    \"\"\"Trigger FULL EXT scan manually from UI (Settings tab).\"\"\"
    import subprocess, time, json
    from flask import request, jsonify

    data = request.get_json(silent=True) or {}
    src = data.get("src", "/home/test/Data/SECURITY_BUNDLE")
    profile = data.get("profile", "ext")

    ts = time.strftime("%Y%m%d_%H%M%S")
    run_id = f"RUN_VSP_FULL_EXT_UI_{ts}"

    cmd = [
        "/home/test/Data/SECURITY_BUNDLE/bin/run_vsp_full_ext_from_ui.sh",
        src,
        profile,
        run_id,
    ]

    try:
        subprocess.Popen(cmd)
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

    return jsonify({
        "ok": True,
        "run_id": run_id,
        "message": "Scan started",
        "cmd": " ".join(cmd),
    }), 200

"""

text = text + "\n" + append_block
p.write_text(text, encoding="utf-8")

print("[OK] Patched /api/vsp/run_scan with new function")
