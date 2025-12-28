#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

backup="$APP.bak_metrics_top_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$backup"
echo "[BACKUP] $APP -> $backup"

python - << 'PY'
import pathlib

MARKER = "# ========== VSP_METRICS_TOP_V1 START =========="

app_path = pathlib.Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

if MARKER in txt:
    print("[INFO] Đã có block VSP_METRICS_TOP_V1, bỏ qua.")
else:
    block = """
# ========== VSP_METRICS_TOP_V1 START ==========
import json
import logging
from collections import Counter
from pathlib import Path
from flask import request

logger = logging.getLogger(__name__)

_VSP_RISKY_SEVERITIES_TOP = {"CRITICAL", "HIGH"}

def _vsp_root_dir_from_ui_top():
    try:
        return Path(__file__).resolve().parent.parent
    except Exception:
        return Path(".")

def _vsp_find_report_dir_top(latest_run_id):
    try:
        root = _vsp_root_dir_from_ui_top()
        report_dir = root / "out" / latest_run_id / "report"
        if report_dir.is_dir():
            return report_dir
    except Exception as exc:
        logger.warning("[VSP_METRICS_TOP] Cannot resolve report dir for %s: %s", latest_run_id, exc)
    return None

def _vsp_load_findings_top(report_dir: Path):
    f = report_dir / "findings_unified.json"
    if not f.exists():
        logger.info("[VSP_METRICS_TOP] %s không tồn tại – bỏ qua top_*", f)
        return []

    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.warning("[VSP_METRICS_TOP] Lỗi đọc %s: %s", f, exc)
        return []

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        if isinstance(data.get("findings"), list):
            return data["findings"]
        if isinstance(data.get("items"), list):
            return data["items"]
    return []

def _vsp_extract_cwe_top(f: dict):
    for key in ("cwe_id", "cwe", "cwe_code", "cweid"):
        val = f.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return None

def _vsp_extract_module_top(f: dict):
    for key in ("dependency", "package", "package_name", "module", "component", "image", "target", "resource"):
        val = f.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return None

def _vsp_compute_top_metrics_top(latest_run_id: str) -> dict:
    report_dir = _vsp_find_report_dir_top(latest_run_id)
    if not report_dir:
        return {}

    findings = _vsp_load_findings_top(report_dir)
    if not findings:
        return {}

    by_tool = Counter()
    by_cwe = Counter()
    by_module = Counter()

    for item in findings:
        if not isinstance(item, dict):
            continue
        sev = str(item.get("severity", "")).upper()
        if sev not in _VSP_RISKY_SEVERITIES_TOP:
            continue

        tool = item.get("tool") or item.get("source")
        if isinstance(tool, str) and tool.strip():
            by_tool[tool.strip()] += 1

        cwe = _vsp_extract_cwe_top(item)
        if cwe:
            by_cwe[cwe] += 1

        module = _vsp_extract_module_top(item)
        if module:
            by_module[module] += 1

    result: dict[str, object] = {}

    if by_tool:
        tool, n = by_tool.most_common(1)[0]
        result["top_risky_tool"] = {
            "id": tool,
            "label": tool,
            "crit_high": int(n),
        }

    if by_cwe:
        cwe, n = by_cwe.most_common(1)[0]
        result["top_impacted_cwe"] = {
            "id": cwe,
            "label": cwe,
            "crit_high": int(n),
        }

    if by_module:
        module, n = by_module.most_common(1)[0]
        result["top_vulnerable_module"] = {
            "id": module,
            "label": module,
            "crit_high": int(n),
        }

    return result

@app.after_request
def vsp_metrics_after_request_top_v1(response):
    \"\"\"Hậu xử lý riêng cho Dashboard V3 để bơm top_* nếu thiếu.\"\"\"
    try:
        path = request.path
    except RuntimeError:
        return response

    if path != "/api/vsp/dashboard_v3":
        return response

    mimetype = response.mimetype or ""
    if not mimetype.startswith("application/json"):
        return response

    try:
        data = json.loads(response.get_data(as_text=True) or "{}")
    except Exception:
        logger.warning("[VSP_METRICS_TOP] Không parse được JSON từ %s", path)
        return response

    latest_run_id = data.get("latest_run_id")
    if not isinstance(latest_run_id, str) or not latest_run_id:
        return response

    top = _vsp_compute_top_metrics_top(latest_run_id)
    if not top:
        return response

    for key in ("top_risky_tool", "top_impacted_cwe", "top_vulnerable_module"):
        if key in top and not data.get(key):
            data[key] = top[key]

    new_body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    response.set_data(new_body)
    response.headers["Content-Length"] = str(len(new_body))
    return response

# ========== VSP_METRICS_TOP_V1 END ==========
"""

    txt = txt.rstrip() + "\n\n" + block.lstrip() + "\n"
    app_path.write_text(txt, encoding="utf-8")
    print("[OK] Đã append block VSP_METRICS_TOP_V1.")
PY

echo "[DONE] patch_vsp_demo_app_metrics_top_v1.sh hoàn tất."
