#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

BAK="$APP.bak_run_dast_stub_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BAK"
echo "[BACKUP] $APP -> $BAK"

python - << PY
from pathlib import Path

app_path = Path(r"$APP")
txt = app_path.read_text(encoding="utf-8")

if "def api_vsp_run(" in txt:
    print("[PATCH] api_vsp_run đã tồn tại, bỏ qua (không chèn lại).")
    raise SystemExit(0)

block = """

# === VSP 2025 – SIMPLE RUN + DAST API STUB V1 ===
@app.route("/api/vsp/run", methods=["POST"])
def api_vsp_run():
    \"\"\"Trigger scan LOCAL (stub).

    Ý tưởng:
    - Sau này nối thật vào bin/run_vsp_full_ext.sh hoặc VSP_CI_OUTER.
    - Bản hiện tại chỉ log request + trả về run_id stub cho UI.
    \"\"\"
    from flask import request, jsonify
    from datetime import datetime
    import logging

    payload = request.get_json(silent=True) or {}
    mode = payload.get("mode") or "local"
    profile = payload.get("profile") or "FULL_EXT"
    target_type = payload.get("target_type") or "path"
    target = (payload.get("target") or ".").strip()

    logging.getLogger(__name__).info(
        "[VSP_RUN_API] Received run request mode=%s profile=%s target_type=%s target=%s payload=%s",
        mode, profile, target_type, target, payload,
    )

    # TODO: nối thật vào pipeline scan:
    #  - LOCAL path: SAST / SCA / secrets / IaC (bin/run_vsp_full_ext.sh)
    #  - CI mode: gọi VSP_CI_OUTER
    # Tạm thời trả về stub, để UI không lỗi.
    run_id = "VSP_RUN_STUB_" + datetime.utcnow().strftime("%Y%m%d_%H%M%S")

    return jsonify({
        "ok": False,
        "run_id": run_id,
        "mode": mode,
        "profile": profile,
        "target_type": target_type,
        "target": target,
        "implemented": False,
        "message": "API stub – cần nối với pipeline scan thật (SAST/SCA/secrets/IaC).",
    })


@app.route("/api/vsp/dast/scan", methods=["POST"])
def api_vsp_dast_scan():
    \"\"\"Đăng ký 1 request DAST scan URL/domain (stub Nessus/ZAP-class).

    * KHÔNG phải AATE/ANY-URL.
    * Chỉ ghi log + append vào out/dast_history.json.
    \"\"\"
    from flask import request, jsonify
    from datetime import datetime
    from pathlib import Path
    import json

    payload = request.get_json(silent=True) or {}
    url = (payload.get("url") or payload.get("target") or "").strip()

    scan_id = "DAST_STUB_" + datetime.utcnow().strftime("%Y%m%d_%H%M%S")

    root_dir = Path(__file__).resolve().parent.parent
    hist_path = root_dir / "out" / "dast_history.json"
    hist_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        items = json.loads(hist_path.read_text("utf-8"))
        if not isinstance(items, list):
            items = []
    except Exception:
        items = []

    items.append({
        "scan_id": scan_id,
        "url": url,
        "created_at": datetime.utcnow().isoformat() + "Z",
        "status": "PLANNED",
        "engine": "DAST_STUB_V1 (Nessus/ZAP-class, KHÔNG phải AATE/ANY-URL)",
        "note": "Chức năng DAST đang ở trạng thái planned integration – chưa chạy thực tế.",
    })

    hist_path.write_text(json.dumps(items, indent=2), encoding="utf-8")

    return jsonify({
        "ok": True,
        "scan_id": scan_id,
        "url": url,
        "planned": True,
        "engine": "DAST_STUB_V1",
        "message": "Đã ghi nhận yêu cầu scan URL/domain – engine DAST sẽ được nối sau.",
    })


@app.route("/api/vsp/dast/history", methods=["GET"])
def api_vsp_dast_history():
    \"\"\"Trả về danh sách history các DAST request (stub).\"\"\"
    from flask import jsonify
    from pathlib import Path
    import json

    root_dir = Path(__file__).resolve().parent.parent
    hist_path = root_dir / "out" / "dast_history.json"

    try:
        items = json.loads(hist_path.read_text("utf-8"))
        if not isinstance(items, list):
            items = []
    except Exception:
        items = []

    return jsonify({
        "ok": True,
        "items": items,
    })
# === END VSP 2025 RUN + DAST API STUB V1 ===

"""

marker = 'if __name__ == "__main__":'
if marker in txt:
    new_txt = txt.replace(marker, block + "\\n\\n" + marker)
else:
    new_txt = txt + block

app_path.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chèn block RUN + DAST stub vào vsp_demo_app.py")
PY
