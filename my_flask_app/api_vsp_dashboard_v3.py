from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any

from flask import Blueprint, jsonify, request

# app.py đang gọi api_vsp_dashboard_v3.bp
bp = Blueprint("bp_dashboard_v3", __name__)

# ROOT = /home/test/Data/SECURITY_BUNDLE
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "out"


def _list_runs() -> List[Path]:
    """Liệt kê RUN_* trong out/, sort desc theo mtime (mới nhất trước)."""
    if not OUT_DIR.is_dir():
        return []

    runs: List[Path] = []
    for p in OUT_DIR.iterdir():
        if p.is_dir() and p.name.startswith("RUN_"):
            runs.append(p)

    # Sort theo thời gian sửa cuối, mới nhất trước
    runs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return runs


def _load_summary(run_dir: Path) -> Dict[str, Any] | None:
    """Đọc report/summary_unified.json trong 1 RUN."""
    summary_path = run_dir / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return None

    try:
        text = summary_path.read_text(encoding="utf-8")
        return json.loads(text)
    except Exception:
        return None


@bp.route("/api/vsp/dashboard_v3", methods=["GET"])
def dashboard_v3():
    """
    CIO dashboard entry – contract chuẩn:
    {
      "ok": true/false,
      "latest_run_id": "RUN_..." | null,
      "runs_recent": ["RUN_...", ...],
      "summary_all": {...},
      "by_severity": {...},
      "by_tool": {...},
      "error": "..." (optional)
    }
    """
    runs = _list_runs()
    resp: Dict[str, Any] = {
        "ok": True,
        "latest_run_id": None,
        "runs_recent": [],
        "summary_all": {},
        "by_severity": {},
        "by_tool": {},
    }

    if not runs:
        resp["ok"] = False
        resp["error"] = f"No runs found under {OUT_DIR}"
        return jsonify(resp)

    # Tìm RUN mới nhất CÓ summary_unified.json
    latest = None
    summary = None
    for r in runs:
        s = _load_summary(r)
        if s is not None:
            latest = r
            summary = s
            break

    if latest is None or summary is None:
        # Không RUN nào có summary => báo lỗi rõ ràng
        resp["ok"] = False
        resp["error"] = f"No summary_unified.json found in any RUN under {OUT_DIR}"
        resp["runs_recent"] = [r.name for r in runs[:20]]
        return jsonify(resp)

    resp["latest_run_id"] = latest.name
    resp["runs_recent"] = [r.name for r in runs[:20]]

    resp["summary_all"] = (
        summary.get("summary_all")
        or summary.get("SUMMARY_ALL")
        or {}
    )
    resp["by_severity"] = (
        summary.get("by_severity")
        or summary.get("BY_SEVERITY")
        or {}
    )
    resp["by_tool"] = (
        summary.get("by_tool")
        or summary.get("BY_TOOL")
        or {}
    )

    # Tính total_findings từ by_severity
    sev = resp["by_severity"] or {}
    total = 0
    for v in sev.values():
        # Case 1: v là dict kiểu {"count": N, ...}
        if isinstance(v, dict):
            try:
                total += int(v.get("count", 0) or 0)
            except Exception:
                pass
        # Case 2: v là số trực tiếp (int/float)
        elif isinstance(v, (int, float)):
            try:
                total += int(v)
            except Exception:
                pass

    if isinstance(resp["summary_all"], dict):
        resp["summary_all"].setdefault("total_findings", total)
    resp["total_findings"] = total

    return jsonify(resp)


@bp.route("/api/vsp/runs_index_v3", methods=["GET"])
def runs_index_v3():
    """
    Contract chuẩn:
    {
      "ok": true,
      "items": [
        {
          "run_id": "...",
          "created_at": "ISO8601",
          "profile": "FULL_EXT",
          "target": "/home/test/Data/khach6",
          "totals": { "CRITICAL": 1, ... }
        },
        ...
      ]
    }
    """
    try:
        limit = request.args.get("limit", type=int) or 200
    except Exception:
        limit = 200

    runs = _list_runs()[:limit]
    items: List[Dict[str, Any]] = []

    for run_dir in runs:
        summary = _load_summary(run_dir) or {}

        # created_at từ mtime thư mục
        try:
            created_at = datetime.fromtimestamp(
                run_dir.stat().st_mtime
            ).isoformat()
        except Exception:
            created_at = ""

        profile = (
            summary.get("profile")
            or summary.get("PROFILE")
            or ""
        )
        target = (
            summary.get("source_root")
            or summary.get("target_url")
            or summary.get("SOURCE_ROOT")
            or summary.get("TARGET_URL")
            or ""
        )

        by_severity = (
            summary.get("by_severity")
            or summary.get("BY_SEVERITY")
            or {}
        )

        items.append(
            {
                "run_id": run_dir.name,
                "created_at": created_at,
                "profile": profile,
                "target": target,
                "totals": by_severity,
            }
        )

    return jsonify(ok=True, items=items)
