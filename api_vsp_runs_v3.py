from __future__ import annotations

import json
from pathlib import Path
from flask import Blueprint, jsonify, send_file, request, abort

bp_runs_v3 = Blueprint("bp_runs_v3", __name__)

# BUNDLE_ROOT: /home/test/Data/SECURITY_BUNDLE
BUNDLE_ROOT = Path(__file__).resolve().parents[1]
OUT_ROOT = BUNDLE_ROOT / "out"


@bp_runs_v3.route("/vsp/runs_index_v3")
def vsp_runs_index_v3():
    """
    Trả danh sách các RUN_* trong thư mục out/ để hiển thị tab Runs & Reports.
    Đọc nhẹ từ report/summary_unified.json nếu có.
    """
    try:
        limit = int(request.args.get("limit", "100"))
    except ValueError:
        limit = 100

    items = []

    if not OUT_ROOT.is_dir():
        return jsonify(ok=False, error=f"OUT_ROOT not found: {OUT_ROOT}"), 500

    run_dirs = [
        p for p in OUT_ROOT.iterdir()
        if p.is_dir() and p.name.startswith("RUN_")
    ]

    # Run mới nhất lên đầu
    run_dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    for run_dir in run_dirs[:limit]:
        run_id = run_dir.name
        summary_path = run_dir / "report" / "summary_unified.json"

        profile = None
        started_at = None
        duration_sec = None
        total_findings = None
        posture_score = None
        severity_max = None

        if summary_path.is_file():
            try:
                data = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception:
                data = {}

            profile = data.get("profile") or data.get("profile_name")
            started_at = data.get("started_at")
            duration_sec = data.get("duration_sec")

            summary_all = data.get("summary_all") or {}
            total_findings = summary_all.get("total_findings")
            posture_score = summary_all.get("posture_score")
            severity_max = summary_all.get("severity_max")

        item = {
            "run_id": run_id,
            "profile": profile,
            "started_at": started_at,
            "duration_sec": duration_sec,
            "total_findings": total_findings,
            "posture_score": posture_score,
            "severity_max": severity_max,
        }
        items.append(item)

    return jsonify(ok=True, items=items)


@bp_runs_v3.route("/vsp/run_export_v3")
def vsp_run_export_v3():
    """
    Direct export HTML/ZIP cho 1 run – chạy trên UI gateway.
    Query:
      - run_id: tên thư mục RUN_* trong out/
      - fmt: html | zip
    """
    run_id = request.args.get("run_id")
    fmt = (request.args.get("fmt") or "html").lower()

    if not run_id:
        return jsonify(ok=False, error="Missing run_id"), 400

    run_dir = OUT_ROOT / run_id
    if not run_dir.is_dir():
        abort(404, description=f"Run not found: {run_id}")

    if fmt == "html":
        candidates = [
            run_dir / "report" / "report_vsp_full.html",
            run_dir / "report" / "report_unified.html",
            run_dir / "report" / "report.html",
        ]
        for path in candidates:
            if path.is_file():
                return send_file(
                    path,
                    mimetype="text/html",
                    as_attachment=False,
                    download_name=f"{run_id}.html",
                )
        abort(404, description=f"No HTML report found for {run_id}")

    elif fmt == "zip":
        candidates = [
            run_dir / "report" / "report_bundle_vsp_full.zip",
            run_dir / "report" / "report_bundle.zip",
            run_dir / "report" / "report.zip",
        ]
        for path in candidates:
            if path.is_file():
                return send_file(
                    path,
                    mimetype="application/zip",
                    as_attachment=True,
                    download_name=f"{run_id}_report_bundle.zip",
                )
        abort(404, description=f"No ZIP bundle found for {run_id}")

    else:
        return jsonify(ok=False, error=f"Unsupported fmt: {fmt}"), 400
