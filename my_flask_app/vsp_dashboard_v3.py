from flask import Blueprint, jsonify
from pathlib import Path
import json
import os

bp = Blueprint("vsp_dashboard_v3", __name__)

# Auto detect ROOT = /home/test/Data/SECURITY_BUNDLE
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "out"


def _get_latest_vsp_run_dir():
    """
    Tìm RUN VSP FULL EXT:
      1) Nếu có env VSP_RUN_DIR thì ưu tiên dùng.
      2) Nếu không, tìm RUN_VSP_FULL_EXT_* mới nhất có summary_unified.json.
    """
    env_run = os.environ.get("VSP_RUN_DIR")
    if env_run:
        p = Path(env_run)
        if p.is_dir() and (p / "report" / "summary_unified.json").is_file():
            print(f"[VSP] dashboard_v3: dùng VSP_RUN_DIR={p}")
            return p
        else:
            print(f"[VSP][WARN] VSP_RUN_DIR={env_run} không hợp lệ.")

    candidates = sorted(OUT_DIR.glob("RUN_VSP_FULL_EXT_*"), reverse=True)
    for c in candidates:
        if (c / "report" / "summary_unified.json").is_file():
            print(f"[VSP] dashboard_v3: auto chọn run={c.name}")
            return c

    print("[VSP][ERR] Không tìm thấy RUN_VSP_FULL_EXT_* nào có summary_unified.json")
    return None


def _safe_int(val):
    try:
        return int(val)
    except Exception:
        try:
            return int(float(val))
        except Exception:
            return 0


# [DISABLED] legacy dashboard_v3 route (đã chuyển sang vsp_api_v3)
# @bp.route("/api/vsp/dashboard_v3", methods=["GET"])
def _vsp_dashboard_v3_legacy_disabled():
    run_dir = _get_latest_vsp_run_dir()
    if not run_dir:
        return jsonify({
            "ok": False,
            "error": "No VSP FULL EXT run found (RUN_VSP_FULL_EXT_*)."
        }), 404

    summary_path = run_dir / "report" / "summary_unified.json"
    try:
        with summary_path.open(encoding="utf-8") as f:
            summary = json.load(f)
    except Exception as exc:
        print(f"[VSP][ERR] Đọc summary_unified.json lỗi: {exc}")
        return jsonify({
            "ok": False,
            "error": f"Cannot read summary_unified.json: {exc}"
        }), 500

    run_id = summary.get("run_id") or run_dir.name

    raw_sev = (
        summary.get("severity")
        or (summary.get("summary") or {}).get("by_severity")
        or {}
    )

    sev = {
        "CRITICAL": _safe_int(raw_sev.get("CRITICAL", 0)),
        "HIGH":     _safe_int(raw_sev.get("HIGH", 0)),
        "MEDIUM":   _safe_int(raw_sev.get("MEDIUM", 0)),
        "LOW":      _safe_int(raw_sev.get("LOW", 0)),
        "INFO":     _safe_int(raw_sev.get("INFO", 0)),
        "TRACE":    _safe_int(raw_sev.get("TRACE", 0)),
    }

    total_findings = summary.get("total_findings")
    if total_findings is None:
        total_findings = sum(sev.values())
    total_findings = _safe_int(total_findings)

    security_score = summary.get("security_score")

    # Top risky tool
    top_risky_tool = "-"
    by_tool = (summary.get("summary") or {}).get("by_tool") or {}
    best_tool = None
    best_val = -1
    for tool_name, meta in by_tool.items():
        if isinstance(meta, dict):
            val = meta.get("total") or meta.get("TOTAL") or meta.get("count") or 0
        else:
            val = meta or 0
        v = _safe_int(val)
        if v > best_val:
            best_val = v
            best_tool = tool_name
    if best_tool:
        top_risky_tool = best_tool

    # Top CWE
    top_cwe = "-"
    by_cwe = (summary.get("summary") or {}).get("by_cwe") or {}
    best_cwe = None
    best_val = -1
    for cwe_id, meta in by_cwe.items():
        if isinstance(meta, dict):
            val = meta.get("total") or meta.get("TOTAL") or meta.get("count") or 0
        else:
            val = meta or 0
        v = _safe_int(val)
        if v > best_val:
            best_val = v
            best_cwe = cwe_id
    if best_cwe:
        top_cwe = best_cwe

    # Top module
    top_module = "-"
    by_module = (summary.get("summary") or {}).get("by_module") or {}
    best_mod = None
    best_val = -1
    for mod, meta in by_module.items():
        if isinstance(meta, dict):
            val = meta.get("total") or meta.get("TOTAL") or meta.get("count") or 0
        else:
            val = meta or 0
        v = _safe_int(val)
        if v > best_val:
            best_val = v
            best_mod = mod
    if best_mod:
        top_module = best_mod

    payload = {
        "ok": True,
        "run_id": run_id,
        "total_findings": total_findings,
        "security_score": security_score,
        "by_severity": sev,
        "severity": sev,
        "top_risky_tool": top_risky_tool,
        "top_cwe": top_cwe,
        "top_module": top_module,
        "ts": summary.get("ts"),
    }

    print(f"[VSP] dashboard_v3: run={run_id}, total_findings={total_findings}, score={security_score}")
    return jsonify(payload)
