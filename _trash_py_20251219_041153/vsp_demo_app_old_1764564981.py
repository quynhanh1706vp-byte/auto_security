from __future__ import annotations

import datetime
import json
from pathlib import Path
from typing import Optional, Any

from flask import (




# ===== VSP helpers (dashboard/datasource) =====
def _vsp_get_runs_root():
    from pathlib import Path
    root = Path(__file__).resolve().parent.parent
    runs_root = root / "out"
    return root, runs_root


def _vsp_discover_run_dirs(limit: int = 50):
    _root, runs_root = _vsp_get_runs_root()
    if not runs_root.is_dir():
        return []
    dirs = [p for p in runs_root.iterdir() if p.is_dir() and p.name.startswith("RUN_")]
    dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return dirs[:limit]


def _vsp_get_latest_run_with_unified():
    for d in _vsp_discover_run_dirs(limit=50):
        summary = d / "report" / "summary_unified.json"
        findings = d / "report" / "findings_unified.json"
        if summary.is_file() or findings.is_file():
            return d
    return None


def _vsp_load_summary_unified(run_dir):
    import json
    summary_path = run_dir / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return {}
    try:
        return json.loads(summary_path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _vsp_load_findings_unified(run_dir):
    import json
    findings_path = run_dir / "report" / "findings_unified.json"
    if not findings_path.is_file():
        return []
    try:
        data = json.loads(findings_path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and "items" in data:
            return data.get("items") or []
        if isinstance(data, list):
            return data
        return []
    except Exception:
        return []


@app.get("/api/vsp/dashboard")
def api_vsp_dashboard():
    """
    CIO Dashboard – đọc summary_unified.json từ RUN full EXT+ mới nhất.
    """
    from flask import jsonify
    import datetime as dt

    run_dir = _vsp_get_latest_run_with_unified()
    if run_dir is None:
        return jsonify(
            ok=True,
            run_id=None,
            total_findings=0,
            severity={k: 0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]},
            by_tool={},
            ts=None,
            extra_charts={},
        )

    summary = _vsp_load_summary_unified(run_dir)
    sev = summary.get("severity") or summary.get("by_severity") or {}
    total = summary.get("total_findings") or summary.get("total") or 0
    by_tool = summary.get("by_tool") or summary.get("tools") or {}

    sev_norm = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
    for k, v in sev.items():
        k_up = str(k).upper()
        if k_up in sev_norm:
            sev_norm[k_up] = int(v or 0)

    try:
        ts = dt.datetime.fromtimestamp(run_dir.stat().st_mtime).isoformat(timespec="seconds")
    except Exception:
        ts = None

    return jsonify(
        ok=True,
        run_id=run_dir.name,
        total_findings=int(total),
        severity=sev_norm,
        by_tool=by_tool,
        ts=ts,
        extra_charts=summary.get("extra_charts") or {},
    )


@app.get("/api/vsp/datasource")
def api_vsp_datasource():
    """
    Data Source – bảng findings_unified.json.
    - mode=dashboard: trả summary nhẹ cho Dashboard (fallback).
    - mặc định: trả items + filter/paging.
    Query:
      - severity
      - tool
      - limit (default 200)
      - offset (default 0)
      - search (chuỗi tìm trong message/file/rule_id)
    """
    from flask import request, jsonify

    mode = (request.args.get("mode") or "").strip()
    run_dir = _vsp_get_latest_run_with_unified()

    if run_dir is None:
        if mode == "dashboard":
            return jsonify(ok=True, run_id=None, summary=None)
        return jsonify(ok=True, run_id=None, total=0, items=[])

    # --- summary mode (dashboard) ---
    if mode == "dashboard":
        summary = _vsp_load_summary_unified(run_dir)
        sev = summary.get("severity") or summary.get("by_severity") or {}
        total = summary.get("total_findings") or summary.get("total") or 0
        by_tool = summary.get("by_tool") or summary.get("tools") or {}
        sev_norm = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}
        for k, v in sev.items():
            k_up = str(k).upper()
            if k_up in sev_norm:
                sev_norm[k_up] = int(v or 0)
        return jsonify(
            ok=True,
            run_id=run_dir.name,
            summary={
                "total_findings": int(total),
                "severity": sev_norm,
                "by_tool": by_tool,
            },
        )

    # --- table mode ---
    findings = _vsp_load_findings_unified(run_dir)

    q_sev    = (request.args.get("severity") or "").upper().strip()
    q_tool   = (request.args.get("tool") or "").strip()
    q_search = (request.args.get("search") or "").strip().lower()
    try:
        limit = int(request.args.get("limit", "200"))
    except ValueError:
        limit = 200
    try:
        offset = int(request.args.get("offset", "0"))
    except ValueError:
        offset = 0
    limit = max(1, min(limit, 2000))
    offset = max(0, offset)

    def _match(rec):
        sev = str(rec.get("severity") or "").upper()
        tool = str(rec.get("tool") or "")
        if q_sev and sev != q_sev:
            return False
        if q_tool and tool != q_tool:
            return False
        if q_search:
            msg  = str(rec.get("message") or "")
            file = str(rec.get("file") or "")
            rule = str(rec.get("rule_id") or "")
            blob = " ".join([msg, file, rule]).lower()
            if q_search not in blob:
                return False
        return True

    filtered = [r for r in findings if _match(r)]
    total = len(filtered)
    slice_ = filtered[offset:offset+limit]

    for idx, rec in enumerate(slice_, start=offset+1):
        rec.setdefault("id", idx)

    return jsonify(
        ok=True,
        run_id=run_dir.name,
        total=total,
        limit=limit,
        offset=offset,
        items=slice_,
    )

if __name__ == "__main__":
    # Dev server cho VSP demo
    app.run(host="0.0.0.0", port=8910, debug=False)


@app.route("/security_bundle")
def vsp_index():
    return render_template("vsp_index.html")
