from __future__ import annotations
from flask import Blueprint, jsonify, request
from pathlib import Path
import traceback
import sys

from .common_vsp_latest_run import (
    get_latest_valid_run,
    load_json,
)

bp = Blueprint("vsp_dashboard_api", __name__)


@bp.route("/api/vsp/dashboard_v2", methods=["GET"])
def api_vsp_dashboard_v2():
    """
    Dashboard backend:
      - Nếu run_id không truyền → tự lấy RUN FULL_EXT mới nhất
      - Luôn fallback nếu thiếu file
    """
    try:
        requested_run = request.args.get("run_id")
        run_id = None
        summary_path = None

        # Nếu truyền run_id → cố gắng dùng run đó
        if requested_run:
            run_dir = Path(__file__).resolve().parents[2] / "out" / requested_run
            cand = run_dir / "report" / "summary_unified.json"
            if cand.is_file():
                run_id = requested_run
                summary_path = cand

        # Nếu không truyền hoặc run_id sai → lấy RUN FULL_EXT hợp lệ mới nhất
        if summary_path is None:
            d, s_path = get_latest_valid_run()
            if d is None:
                return jsonify({"ok": False, "error": "No valid RUN found"}), 404
            run_id = d.name
            summary_path = s_path

        summary = load_json(summary_path)
        if summary is None:
            return jsonify({"ok": False, "error": f"Cannot load summary for {run_id}"}), 500

        by_sev = summary.get("by_severity") or summary.get("summary", {}).get("by_severity") or {}
        total = sum(v for v in by_sev.values() if isinstance(v, (int, float)))

        payload = {
            "ok": True,
            "run_id": run_id,
            "total_findings": total,
            "by_severity": by_sev,
            "security_score": summary.get("security_score", 0),
            "top_risky_tool": summary.get("top_risky_tool"),
            "top_cwe": summary.get("top_cwe"),
            "top_module": summary.get("top_module"),
        }

        return jsonify(payload)

    except Exception as e:
        print(f"[DASH_V2][FATAL] {e}", file=sys.stderr)
        traceback.print_exc()
        return jsonify({"ok": False, "error": str(e)}), 500
