#!/usr/bin/env bash
set -euo pipefail

# Thư mục chứa vsp_demo_app.py
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
FILE="$ROOT/vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE"
  exit 1
fi

# Nếu đã có API rồi thì bỏ qua
if grep -q "api_vsp_datasource" "$FILE"; then
  echo "[SKIP] api_vsp_datasource đã tồn tại trong vsp_demo_app.py, bỏ qua."
  exit 0
fi

echo "[i] Backup file gốc..."
cp "$FILE" "${FILE}.bak_$(date +%Y%m%d_%H%M%S)"

echo "[i] Append API Data Source vào cuối file..."

cat >> "$FILE" << 'PYEOF'

# ======= VSP Data Source API v1 (AUTO PATCH) =======
from collections import Counter
from typing import Optional
from pathlib import Path

def _load_run_dir(run_id: Optional[str] = None) -> Optional[Path]:
    """
    Load a specific run directory by run_id, or return the latest run if run_id is None.
    """
    base = RUN_ROOT  # RUN_ROOT đã được khai báo phía trên
    if run_id:
        candidate = base / run_id
        if candidate.is_dir():
            return candidate
        return None

    # Fallback: dùng helper có sẵn (nếu có)
    if "_get_latest_run" in globals():
        return _get_latest_run()
    return None


@app.route("/api/vsp/datasource", methods=["GET"])
def api_vsp_datasource():
    """
    Unified findings cho tab Data Source.
    Optional query: run_id=<RUN_ID>
    Trả về:
      - run_id: tên thư mục RUN_...
      - total: tổng số findings
      - severity_counts: đếm theo CRITICAL/HIGH/...
      - tool_counts: đếm theo từng tool
      - findings: list đầy đủ findings_unified
    """
    run_id = request.args.get("run_id") or None
    run_dir = _load_run_dir(run_id)

    if not run_dir:
        return jsonify({
            "ok": False,
            "error": "Run directory not found.",
            "findings": [],
            "severity_counts": {},
            "tool_counts": {}
        }), 404

    findings_path = run_dir / "report" / "findings_unified.json"
    if not findings_path.is_file():
        return jsonify({
            "ok": False,
            "error": f"Missing findings_unified.json in {run_dir}",
            "findings": [],
            "severity_counts": {},
            "tool_counts": {}
        }), 404

    try:
        raw = findings_path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except Exception as exc:
        return jsonify({
            "ok": False,
            "error": f"Cannot parse findings_unified.json: {exc}",
            "findings": [],
            "severity_counts": {},
            "tool_counts": {}
        }), 500

    if not isinstance(data, list):
        return jsonify({
            "ok": False,
            "error": "findings_unified.json must be a list.",
            "findings": [],
            "severity_counts": {},
            "tool_counts": {}
        }), 500

    sev_counter = Counter()
    tool_counter = Counter()
    findings = []

    for item in data:
        if not isinstance(item, dict):
            continue
        sev = (item.get("severity") or "INFO").upper()
        tool = (item.get("tool") or "unknown").lower()
        sev_counter[sev] += 1
        tool_counter[tool] += 1
        findings.append(item)

    return jsonify({
        "ok": True,
        "run_id": run_dir.name,
        "total": len(findings),
        "severity_counts": dict(sev_counter),
        "tool_counts": dict(tool_counter),
        "findings": findings
    })
# ======= END VSP Data Source API v1 =======

PYEOF

echo "[OK] Đã append API Data Source vào $FILE"
