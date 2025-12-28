from __future__ import annotations

from flask import Blueprint
from .api_vsp_dashboard_v3 import runs_index_v3 as _runs_index_impl

# Blueprint cũ, app.py đang app.register_blueprint(vsp_runs_index_v3.bp)
bp = Blueprint("vsp_runs_index_v3", __name__)

@bp.route("/api/vsp/runs_index_v3", methods=["GET"])
def runs_index_v3():
    """
    Delegate sang implementation chuẩn ở api_vsp_dashboard_v3.runs_index_v3.
    Điều này đảm bảo mọi nơi gọi /api/vsp/runs_index_v3 đều nhận
    cùng một JSON contract:
        { "ok": true, "items": [ ... ] }
    """
    return _runs_index_impl()
