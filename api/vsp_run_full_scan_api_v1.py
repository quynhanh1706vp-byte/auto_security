from flask import Blueprint, jsonify, request
from pathlib import Path
import subprocess

bp_run_full_scan = Blueprint("bp_run_full_scan", __name__)

# File này nằm ở: SECURITY_BUNDLE/ui/api/vsp_run_full_scan_api_v1.py
# -> ROOT_VSP = parents[2] = /home/test/Data/SECURITY_BUNDLE
_ROOT_VSP = Path(__file__).resolve().parents[2]

@bp_run_full_scan.route("/api/vsp/run_full_scan", methods=["POST"])
def api_run_full_scan():
    """
    Trigger FULL scan từ UI gateway (port 8910).
    Gọi bin/vsp_selfcheck_full ở ROOT_VSP.
    """
    payload = request.get_json(silent=True) or {}
    profile = payload.get("profile")
    source_root = payload.get("source_root")
    target_url = payload.get("target_url")

    script = _ROOT_VSP / "bin" / "vsp_selfcheck_full"

    if not script.is_file():
        return jsonify(
            ok=False,
            error=f"Script not found: {script}",
        ), 500

    try:
        proc = subprocess.Popen(
            [str(script)],
            cwd=str(_ROOT_VSP),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        return jsonify(
            ok=False,
            error=f"Failed to start scan: {e}",
        ), 500

    return jsonify(
        ok=True,
        message="FULL scan started",
        cmd=str(script),
        pid=proc.pid,
        profile=profile,
        source_root=source_root,
        target_url=target_url,
    )
