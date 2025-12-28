from flask import Flask, jsonify
# from flask_cors import CORS  # disabled temporarily

# Package-relative imports for backend API modules
from . import (
    api_vsp_dashboard_v2,
    api_vsp_dashboard_v3,
    api_vsp_datasource_v2,
    api_vsp_runs_v2,
    api_vsp_runs_index_v3,
    api_vsp_settings_v1,
    api_vsp_insights_v1,
)

app = Flask(__name__)
# CORS(app)  # disabled temporarily

# Register all back-end blueprints
app.register_blueprint(api_vsp_dashboard_v2.bp)
app.register_blueprint(api_vsp_dashboard_v3.bp)
app.register_blueprint(api_vsp_datasource_v2.bp)
app.register_blueprint(api_vsp_runs_v2.bp)
app.register_blueprint(api_vsp_runs_index_v3.bp)
app.register_blueprint(api_vsp_settings_v1.bp_vsp_settings_v1)
app.register_blueprint(api_vsp_insights_v1.bp_insights_v1)

@app.route("/healthz")
def health():
    return jsonify({"ok": True, "msg": "backend core alive"})

if __name__ == "__main__":
    # Khi chạy trực tiếp: coi my_flask_app là package gốc
    app.run(host="0.0.0.0", port=8961, debug=False)


# === VSP_RUN_EXPORT_V3 auto import ===
from api.vsp_run_export_api_v3 import bp_run_export_v3

# === VSP_RUN_EXPORT_V3 auto register ===
app.register_blueprint(bp_run_export_v3)



@app.route("/api/vsp/ci_snapshot_latest", methods=["GET"])
def vsp_ci_snapshot_latest_proxy():
    """
    Proxy từ UI gateway (8910) sang core VSP (8961) cho CI snapshot.
    """
    import os
    import requests
    from flask import current_app, jsonify, Response

    backend = os.environ.get("VSP_CORE_BASE_URL", "http://localhost:8961")
    url = backend.rstrip("/") + "/api/vsp/ci_snapshot_latest"

    try:
        current_app.logger.info("[VSP_UI][CI_SNAPSHOT_PROXY] GET %s", url)
        r = requests.get(url, timeout=10)
    except Exception as e:
        current_app.logger.exception("[VSP_UI][CI_SNAPSHOT_PROXY] Lỗi gọi backend %s", url)
        return jsonify(ok=False, error="backend_unreachable", detail=str(e)), 502

    resp = Response(r.content, status=r.status_code)
    ct = r.headers.get("Content-Type")
    if ct:
        resp.headers["Content-Type"] = ct
    return resp

