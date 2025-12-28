#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
API="$ROOT/api/api_vsp_dashboard_v3.py"

echo "[PATCH] Target: $API"
cp "$API" "$API.bak_passthrough_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path
import textwrap

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/api/api_vsp_dashboard_v3.py")

code = textwrap.dedent("""
    import json
    from pathlib import Path
    from flask import Blueprint, jsonify

    bp_dashboard = Blueprint("bp_dashboard", __name__)

    # ROOT = /home/test/Data/SECURITY_BUNDLE
    ROOT = Path(__file__).resolve().parents[2]


    def load_summary(run_dir: Path):
        \"\"\"Đọc report/summary_unified.json của 1 RUN_VSP_FULL_EXT_*\"\"\"
        p = run_dir / "report" / "summary_unified.json"
        if not p.is_file():
            return None
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:
            # Nếu JSON lỗi thì trả None để API báo lỗi rõ ràng
            print("[VSP_DASHBOARD_V3] Lỗi load", p, "=>", e)
            return None


    @bp_dashboard.route("/api/vsp/dashboard_v3", methods=["GET"])
    def dashboard_v3():
        \"\"\"Dashboard V3 – trả summary_unified.json + vài meta cơ bản.

        Cấu trúc response:

        {
          "ok": true,
          "latest_run_id": "RUN_VSP_FULL_EXT_...",
          "runs_recent": ["RUN_VSP_FULL_EXT_...", ...],
          ... toàn bộ field trong summary_unified.json (summary_all, summary_by_severity, by_tool, ...)
        }
        \"\"\"
        out_dir = ROOT / "out"
        runs = sorted(out_dir.glob("RUN_VSP_FULL_EXT_*"), reverse=True)
        if not runs:
            return jsonify(ok=False, error="No runs found")

        latest = runs[0]
        summary = load_summary(latest)
        if not summary:
            return jsonify(
                ok=False,
                latest_run_id=latest.name,
                error="summary_unified.json not found or invalid",
            )

        resp = {
            "ok": True,
            "latest_run_id": latest.name,
            "runs_recent": [r.name for r in runs[:20]],
        }

        # Pass-through toàn bộ nội dung summary_unified.json lên response
        # => FE có thể đọc summary_all, summary_by_severity, by_tool, ...
        if isinstance(summary, dict):
            resp.update(summary)

        return jsonify(resp)
""").lstrip("\\n")

p.write_text(code, encoding="utf-8")
print("[OK] Đã ghi lại api_vsp_dashboard_v3.py với bản passthrough summary_unified.json.")
PY
