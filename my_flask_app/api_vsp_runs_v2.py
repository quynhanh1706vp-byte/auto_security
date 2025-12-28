from __future__ import annotations

from flask import Blueprint, jsonify, current_app, request
from pathlib import Path
import os
import json
import sys
import traceback

bp = Blueprint("vsp_runs_v2", __name__)


def _get_vsp_root() -> Path:
    env_root = os.environ.get("VSP_ROOT")
    if env_root:
        return Path(env_root).resolve()

    try:
        cfg = getattr(current_app, "config", {})
        cfg_root = cfg.get("VSP_ROOT") or cfg.get("VSP_ROOT_DIR")
        if cfg_root:
            return Path(cfg_root).resolve()
    except Exception:
        pass

    return Path(__file__).resolve().parents[2]


def _load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"[RUNS_V2][ERR] Cannot load JSON {path}: {e}", file=sys.stderr)
        traceback.print_exc()
        return None


@bp.route("/api/vsp/runs_index_v2", methods=["GET"])
def api_vsp_runs_index_v2():
    """
    Trả danh sách các RUN_VSP_FULL_EXT_* mới nhất:
      [
        { run_id, total_findings, by_severity },
        ...
      ]
    """
    try:
        vsp_root = _get_vsp_root()
        out_dir = vsp_root / "out"
        limit = int(request.args.get("limit", 50))

        items = []

        if not out_dir.is_dir():
            return jsonify(items)

        for d in sorted(out_dir.iterdir(), key=lambda p: p.name, reverse=True):
            if not d.is_dir():
                continue
            if not d.name.startswith("RUN_VSP_FULL_EXT_"):
                continue

            rep = d / "report"
            summary_path = rep / "summary_unified.json"
            if not summary_path.is_file():
                continue

            summary = _load_json(summary_path)
            if summary is None:
                continue

            by_sev = summary.get("by_severity") or summary.get("summary", {}).get("by_severity") or {}
            if isinstance(by_sev, dict):
                total = sum(v for v in by_sev.values() if isinstance(v, (int, float)))
            else:
                total = summary.get("total_findings")

            items.append(
                {
                    "run_id": d.name,
                    "total_findings": total,
                    "by_severity": by_sev,
                }
            )

            if len(items) >= limit:
                break

        return jsonify(items)
    except Exception as e:
        print(f"[RUNS_V2][FATAL] {e}", file=sys.stderr)
        traceback.print_exc()
        return jsonify([]), 500
