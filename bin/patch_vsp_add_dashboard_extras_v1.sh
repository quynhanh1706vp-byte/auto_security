#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"
BACKUP="$APP.bak_dashboard_extras_$(date +%Y%m%d_%H%M%S)"

echo "[INFO] UI_ROOT = $UI_ROOT"
echo "[INFO] APP     = $APP"
cp "$APP" "$BACKUP"
echo "[BACKUP] $APP -> $BACKUP"

cd "$UI_ROOT"

python - << 'PY'
from pathlib import Path
import textwrap

app_path = Path("vsp_demo_app.py")
src = app_path.read_text(encoding="utf-8")

if "/api/vsp/dashboard_extras_v1" in src:
    print("[INFO] Route /api/vsp/dashboard_extras_v1 đã tồn tại, bỏ qua.")
else:
    snippet = textwrap.dedent('''
    @app.route("/api/vsp/dashboard_extras_v1")
    def vsp_dashboard_extras_v1():
        """Extras cho Dashboard: top findings, noisy paths, CVE, by_tool – stub V1.

        V1 chỉ wrap lại /api/vsp/dashboard_v3 nếu có, để UI có data tối thiểu.
        Sau này có thể mở rộng để đọc trực tiếp findings_unified.json.
        """
        from flask import jsonify

        base = {}
        try:
            # Gọi lại dashboard_v3 để lấy latest_run_id, by_tool...
            with app.test_client() as c:
                r = c.get("/api/vsp/dashboard_v3")
                if r.is_json:
                    base = r.get_json() or {}
        except Exception as e:
            base = {"error": str(e)}

        by_tool = (
            base.get("by_tool")
            or base.get("summary_by_tool")
            or {}
        )

        payload = {
            "ok": True,
            "latest_run_id": base.get("latest_run_id"),
            # Các field này V1 có thể rỗng, UI sẽ hiển thị 'No data'
            "top_risky": base.get("top_risky") or [],
            "top_noisy_paths": base.get("top_noisy_paths") or [],
            "top_cves": base.get("top_cves") or [],
            "by_tool_severity": by_tool,
        }
        return jsonify(payload)
    ''')

    src = src.rstrip() + "\n\n" + snippet + "\n"
    app_path.write_text(src, encoding="utf-8")
    print("[PATCH] Đã thêm route /api/vsp/dashboard_extras_v1 vào vsp_demo_app.py")
PY

echo "[DONE] Patch vsp_add_dashboard_extras_v1 hoàn tất."
