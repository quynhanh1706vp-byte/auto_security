from __future__ import annotations

import json
from pathlib import Path
from datetime import datetime
from typing import Any, Dict, List

from flask import Blueprint, jsonify, request

bp = Blueprint("vsp_runs_index_v3", __name__, url_prefix="/api/vsp")

# ROOT cố định cho core
ROOT = Path("/home/test/Data/SECURITY_BUNDLE").resolve()


def _parse_ts(value: Any) -> float:
    if not value:
        return 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return 0.0
    txt = value.strip()
    if not txt:
        return 0.0
    if txt.endswith("Z"):
        txt = txt[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(txt)
        return dt.timestamp()
    except Exception:
        return 0.0


def _extract(data: Dict[str, Any], keys: List[str], default: Any = None) -> Any:
    """
    Lấy field từ nhiều layer: data, data['run'], data['env'], data['meta'].
    """
    layers = [data, data.get("run", {}), data.get("env", {}), data.get("meta", {})]
    for key in keys:
        for layer in layers:
            if isinstance(layer, dict) and key in layer and layer.get(key) not in (None, ""):
                return layer.get(key)
    return default


@bp.route("/runs_index_v3", methods=["GET"])
def runs_index_v3():
    """
    Trả danh sách history các RUN_* dựa trên out/RUN_*/report/summary_unified.json (v1).

    Query params:
    - limit (int): số run tối đa trả về (sort DESC theo started_at).
    - profile (str): filter theo profile (EXT, EXT+, FAST, DEMO, ...).
    """
    out_dir = ROOT / "out"

    limit = request.args.get("limit", type=int)
    profile_filter = request.args.get("profile", type=str)

    runs: List[Dict[str, Any]] = []

    if not out_dir.is_dir():
        return jsonify([])

    for run_path in out_dir.glob("RUN_*"):
        if not run_path.is_dir():
            continue

        summary_path = run_path / "report" / "summary_unified.json"
        if not summary_path.is_file():
            continue

        try:
            data = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        # ---- run_id ----
        run_id = _extract(data, ["run_id", "RUN_ID", "id"], default=None)
        if not run_id:
            run_id = run_path.name

        # ---- by_severity ----
        by_severity = _extract(data, ["by_severity", "severity_totals"], default={}) or {}
        if not isinstance(by_severity, dict):
            by_severity = {}

        # ---- total_findings ----
        total_findings_raw = _extract(
            data,
            ["total_findings", "findings_total", "totalIssues", "issues_total"],
            default=None,
        )

        total_from_field = None
        if total_findings_raw is not None:
            try:
                total_from_field = int(total_findings_raw)
            except Exception:
                total_from_field = None

        # Nếu field không có hoặc = 0 thì tính lại từ by_severity
        if total_from_field is None or total_from_field == 0:
            total_from_sev = 0
            for sev in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]:
                try:
                    total_from_sev += int(by_severity.get(sev, 0) or 0)
                except Exception:
                    continue
            total_findings = total_from_sev
        else:
            total_findings = total_from_field

        # ---- profile ----
        profile = _extract(
            data,
            ["profile", "run_profile", "env_profile", "scan_profile", "profile_name"],
            default="UNKNOWN",
        )
        if profile is None or str(profile).strip() == "":
            profile = "UNKNOWN"

        # ---- time fields ----
        started_at = _extract(
            data,
            ["started_at", "start_time", "ts_start", "scan_started_at"],
            default="",
        ) or ""
        finished_at = _extract(
            data,
            ["finished_at", "end_time", "ts_end", "scan_finished_at"],
            default="",
        ) or ""
        duration_sec = _extract(
            data,
            ["duration_sec", "duration_seconds", "scan_duration_sec", "scan_duration"],
            default=None,
        )

        # Filter profile nếu có
        if profile_filter and str(profile).upper() != profile_filter.upper():
            continue

        item: Dict[str, Any] = {
            "run_id": str(run_id),
            "profile": str(profile),
            "total_findings": int(total_findings),
            "by_severity": by_severity,
            "started_at": started_at,
            "finished_at": finished_at,
            "duration_sec": duration_sec,
        }

        # Tách sẵn các trường total_* cho tiện FE
        for sev in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]:
            key = f"total_{sev.lower()}"
            try:
                item[key] = int(by_severity.get(sev, 0) or 0)
            except Exception:
                item[key] = 0

        runs.append(item)

    # Sort theo started_at DESC, fallback run_id
    runs.sort(
        key=lambda x: (_parse_ts(x.get("started_at")), str(x.get("run_id"))),
        reverse=True,
    )

    if limit and limit > 0:
        runs = runs[:limit]

    return jsonify(runs)
