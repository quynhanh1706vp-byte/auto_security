#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

backup="$APP.bak_metrics_top_v3_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$backup"
echo "[BACKUP] $APP -> $backup"

python - << 'PY'
import pathlib

START = "# ========== VSP_METRICS_TOP_V1 START =========="
END   = "# ========== VSP_METRICS_TOP_V1 END =========="

app_path = pathlib.Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

if START not in txt or END not in txt:
    raise SystemExit("[ERR] Không tìm thấy block VSP_METRICS_TOP_V1 trong vsp_demo_app.py")

before, rest = txt.split(START, 1)
_, after = rest.split(END, 1)

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

def _vsp_load_findings_top(report_dir):
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

def _vsp_extract_cwe_top(f):
    # 1) Field trực tiếp
    for key in ("cwe_id", "cwe", "cwe_code", "cweid"):
        val = f.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
        if isinstance(val, list) and val:
            first = val[0]
            if isinstance(first, str) and first.strip():
                return first.strip()
            if isinstance(first, dict):
                for kk in ("id", "code", "name"):
                    v2 = first.get(kk)
                    if isinstance(v2, str) and v2.strip():
                        return v2.strip()

    # 2) Danh sách cwes / cwe_ids
    for key in ("cwes", "cwe_ids"):
        val = f.get(key)
        if isinstance(val, list) and val:
            first = val[0]
            if isinstance(first, str) and first.strip():
                return first.strip()
            if isinstance(first, dict):
                for kk in ("id", "code", "name"):
                    v2 = first.get(kk)
                    if isinstance(v2, str) and v2.strip():
                        return v2.strip()

    # 3) Bên trong extra / metadata
    for key in ("extra", "metadata", "details"):
        sub = f.get(key)
        if isinstance(sub, dict):
            for kk in ("cwe_id", "cwe", "cwe_code", "cweid"):
                val = sub.get(kk)
                if isinstance(val, str) and val.strip():
                    return val.strip()
                if isinstance(val, list) and val:
                    first = val[0]
                    if isinstance(first, str) and first.strip():
                        return first.strip()
                    if isinstance(first, dict):
                        for k2 in ("id", "code", "name"):
                            v2 = first.get(k2)
                            if isinstance(v2, str) and v2.strip():
                                return v2.strip()

    # 4) Tìm trong tags/labels có "CWE-"
    for key in ("tags", "labels", "categories"):
        val = f.get(key)
        if isinstance(val, list):
            for item in val:
                if isinstance(item, str) and "CWE-" in item.upper():
                    return item.strip()

    return None

def _vsp_extract_module_top(f):
    # 1) Các key phổ biến cho module/dependency
    for key in (
        "dependency",
        "package",
        "package_name",
        "module",
        "component",
        "image",
        "image_name",
        "target",
        "resource",
        "resource_name",
        "artifact",
    ):
        val = f.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()

    # 2) Một số tool gói trong extra/metadata
    for key in ("extra", "metadata", "details"):
        sub = f.get(key)
        if isinstance(sub, dict):
            for kk in (
                "dependency",
                "package",
                "package_name",
                "module",
                "component",
                "image",
                "image_name",
                "target",
                "resource",
                "resource_name",
                "artifact",
            ):
                val = sub.get(kk)
                if isinstance(val, str) and val.strip():
                    return val.strip()

    # 3) Fallback: dùng đường dẫn file như "module"
    for key in ("file", "filepath", "path", "location"):
        val = f.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()

    return None

def _vsp_accumulate_top_metrics(findings, risky_only):
    by_tool = Counter()
    by_cwe = Counter()
    by_module = Counter()

    for item in findings:
        if not isinstance(item, dict):
            continue
        sev = str(item.get("severity", "")).upper()
        if risky_only and sev not in _VSP_RISKY_SEVERITIES_TOP:
            continue

        # Tool / engine
        tool = (
            item.get("tool")
            or item.get("source")
            or item.get("scanner")
            or item.get("engine")
            or item.get("engine_id")
            or item.get("provider")
        )
        if isinstance(tool, str) and tool.strip():
            by_tool[tool.strip()] += 1

        cwe = _vsp_extract_cwe_top(item)
        if cwe:
            by_cwe[cwe] += 1

        module = _vsp_extract_module_top(item)
        if module:
            by_module[module] += 1

    return by_tool, by_cwe, by_module

def _vsp_compute_top_metrics_top(latest_run_id):
    report_dir = _vsp_find_report_dir_top(latest_run_id)
    if not report_dir:
        return {}

    findings = _vsp_load_findings_top(report_dir)
    if not findings:
        return {}

    # Pass 1: chỉ CRITICAL/HIGH
    by_tool, by_cwe, by_module = _vsp_accumulate_top_metrics(findings, risky_only=True)

    # Nếu CWE/module không có thì fallback dùng tất cả severity
    if not by_cwe or not by_module:
        by_tool_all, by_cwe_all, by_module_all = _vsp_accumulate_top_metrics(findings, risky_only=False)
        if not by_tool and by_tool_all:
            by_tool = by_tool_all
        if not by_cwe and by_cwe_all:
            by_cwe = by_cwe_all
        if not by_module and by_module_all:
            by_module = by_module_all

    result = {}

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
            "count": int(n),
        }

    if by_module:
        module, n = by_module.most_common(1)[0]
        result["top_vulnerable_module"] = {
            "id": module,
            "label": module,
            "count": int(n),
        }

    return result

@app.after_request
def vsp_metrics_after_request_top_v1(response):
    # Hậu xử lý riêng cho Dashboard V3 để bơm top_* nếu thiếu.
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

new_txt = before + block + after
app_path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã ghi lại block VSP_METRICS_TOP_V1 (V3).")
PY

echo "[DONE] patch_vsp_demo_app_metrics_top_v3.sh hoàn tất."
