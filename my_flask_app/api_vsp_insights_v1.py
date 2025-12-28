from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import Blueprint, jsonify, request, current_app

bp_insights_v1 = Blueprint(
    "vsp_insights_v1",
    __name__,
    url_prefix="/api/vsp/insights",
)

# ---------- helpers: OUT_DIR & RUN ----------

def _get_root_dir() -> Path:
    cfg = getattr(current_app, "config", {})
    root = cfg.get("VSP_ROOT")
    if root:
        return Path(root)
    # fallback: SECURITY_BUNDLE = my_flask_app/../..
    return Path(__file__).resolve().parents[2]


def _get_out_dir() -> Path:
    cfg = getattr(current_app, "config", {})
    out_cfg = cfg.get("VSP_OUT_DIR")
    if out_cfg:
        return Path(out_cfg)
    return _get_root_dir() / "out"


def _find_latest_run(out_dir: Path) -> Optional[str]:
    runs = [p for p in out_dir.glob("RUN_*") if p.is_dir()]
    if not runs:
        return None
    runs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[0].name


def _load_findings_for_run(out_dir: Path, run_id: str) -> List[Dict[str, Any]]:
    run_dir = out_dir / run_id / "report"
    f = run_dir / "findings_unified.json"
    if not f.is_file():
        return []
    data = json.loads(f.read_text(encoding="utf-8"))
    if isinstance(data, dict) and "items" in data:
        return list(data.get("items") or [])
    if isinstance(data, list):
        return data
    return []


_SEV_LEVELS = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]

def _normalize_severity(v: Any) -> str:
    if not v:
        return "INFO"
    s = str(v).upper()
    if s in _SEV_LEVELS:
        return s
    if s in {"CRIT", "BLOCKER"}:
        return "CRITICAL"
    if s in {"WARN"}:
        return "HIGH"
    return "INFO"


def _extract_cwe(item: Dict[str, Any]) -> Optional[str]:
    for key in ("cwe_id", "cwe", "rule_cwe"):
        v = item.get(key)
        if v:
            return str(v)

    tags = item.get("tags") or item.get("labels") or []
    if isinstance(tags, str):
        tags = [tags]
    for t in tags:
        if not isinstance(t, str):
            continue
        if "CWE-" in t:
            idx = t.find("CWE-")
            cand = t[idx:].split()[0].rstrip(",:;")
            return cand
    return None

# ---------- endpoint: /api/vsp/insights/top_cwe_v1 ----------

@bp_insights_v1.route("/top_cwe_v1")
def top_cwe_v1():
    out_dir = _get_out_dir()

    run_id = request.args.get("run_id")
    if not run_id:
        run_id = _find_latest_run(out_dir)
    if not run_id:
        return jsonify({"ok": False, "error": "no_run_found"}), 404

    findings = _load_findings_for_run(out_dir, run_id)

    counts: Dict[str, Dict[str, Any]] = {}
    for it in findings:
        cwe = _extract_cwe(it) or "UNKNOWN"
        sev = _normalize_severity(
            it.get("severity_effective") or it.get("severity")
        )

        entry = counts.setdefault(
            cwe,
            {
                "cwe": cwe,
                "count": 0,
                "by_severity": {k: 0 for k in _SEV_LEVELS},
            },
        )
        entry["count"] += 1
        if sev not in entry["by_severity"]:
            sev = "INFO"
        entry["by_severity"][sev] += 1

    items_sorted = sorted(
        counts.values(),
        key=lambda x: x["count"],
        reverse=True,
    )
    limit = request.args.get("limit", type=int) or 10
    top = items_sorted[:limit]

    return jsonify(
        {
            "ok": True,
            "run_id": run_id,
            "total_cwe": len(counts),
            "items": top,
        }
    )
