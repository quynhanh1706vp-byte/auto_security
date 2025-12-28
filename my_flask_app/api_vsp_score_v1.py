# -*- coding: utf-8 -*-
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import Blueprint, jsonify

SEVERITY_LEVELS = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]

bp = Blueprint("vsp_score_v1", __name__, url_prefix="/api/vsp")


@dataclass
class RunInfo:
    run_id: str
    path: Path
    findings_path: Path
    mtime: float


def _find_security_bundle_root() -> Path:
    p = Path(__file__).resolve()
    for parent in p.parents:
        if (parent / "out").is_dir():
            return parent
    return p.parent


def _find_runs_with_findings(limit: Optional[int] = None) -> List[RunInfo]:
    root = _find_security_bundle_root()
    out_dir = root / "out"
    if not out_dir.is_dir():
        return []

    runs: List[RunInfo] = []
    for child in out_dir.iterdir():
        if not child.is_dir():
            continue
        if not child.name.startswith("RUN_VSP"):
            continue
        findings_path = child / "report" / "findings_unified.json"
        if not findings_path.is_file():
            continue
        mtime = findings_path.stat().st_mtime
        runs.append(
            RunInfo(
                run_id=child.name,
                path=child,
                findings_path=findings_path,
                mtime=mtime,
            )
        )

    runs.sort(key=lambda r: r.mtime, reverse=True)
    if limit is not None:
        runs = runs[:limit]
    return runs


def _load_findings(path: Path) -> List[Dict[str, Any]]:
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and isinstance(data.get("findings"), list):
            return data["findings"]
        return []
    except Exception:
        return []


def _normalize_severity(raw: Optional[str]) -> str:
    if not raw:
        return "INFO"
    s = str(raw).strip().upper()
    if s in SEVERITY_LEVELS:
        return s
    if s in ("BLOCKER", "ERROR"):
        return "CRITICAL"
    if s in ("WARN", "WARNING"):
        return "HIGH"
    if s in ("NOTICE", "MINOR"):
        return "LOW"
    return "INFO"


def _compute_security_score(by_sev: Dict[str, int], total: int) -> int:
    if total <= 0:
        return 100

    crit = by_sev.get("CRITICAL", 0)
    high = by_sev.get("HIGH", 0)
    med = by_sev.get("MEDIUM", 0)
    low = by_sev.get("LOW", 0)

    weighted = 10 * crit + 5 * high + 2 * med + 1 * low
    worst = max(float(total) * 10.0, 1.0)
    penalty_pct = min(100.0, (weighted / worst) * 100.0)
    score = int(round(100.0 - penalty_pct))
    return max(0, min(100, score))


@bp.route("/score_v1", methods=["GET"])
def score_v1():
    """
    API nhẹ: trả về Security Score + by_severity cho run mới nhất.
    """
    runs = _find_runs_with_findings()
    if not runs:
        return jsonify(
            {
                "ok": False,
                "message": "No VSP run with report/findings_unified.json found.",
            }
        )

    latest = runs[0]
    findings = _load_findings(latest.findings_path)

    by_sev: Dict[str, int] = {k: 0 for k in SEVERITY_LEVELS}
    for item in findings:
        sev = item.get("severity_effective") or item.get("severity_raw") or item.get("severity")
        sev_norm = _normalize_severity(sev)
        by_sev[sev_norm] = by_sev.get(sev_norm, 0) + 1

    total = sum(by_sev.values())
    score = _compute_security_score(by_sev, total)

    resp = {
        "ok": True,
        "run_id": latest.run_id,
        "run_dir": str(latest.path),
        "total_findings": total,
        "by_severity": by_sev,
        "security_score": score,
    }
    return jsonify(resp)
