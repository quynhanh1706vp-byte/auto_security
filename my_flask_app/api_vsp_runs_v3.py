from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, Any, List

from flask import Blueprint, jsonify

bp_runs = Blueprint("bp_runs_v3", __name__)

# ROOT = thư mục chứa SECURITY_BUNDLE (tự tính từ vị trí file này)
ROOT = Path(__file__).resolve().parents[2]


def _find_out_root() -> Path:
    """
    Tìm thư mục 'out' gần nhất tính từ ROOT.
    Ưu tiên ROOT / "out", nếu không có thì đi lên trên.
    """
    cur = ROOT
    for _ in range(5):
        candidate = cur / "out"
        if candidate.is_dir():
            return candidate
        cur = cur.parent
    # fallback – vẫn trả ROOT/out để đỡ crash
    return ROOT / "out"


def _load_json(path: Path) -> Optional[Dict[str, Any]]:
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def _parse_timestamp_from_run_id(run_id: str) -> Optional[str]:
    """
    Parse timestamp từ run_id dạng:
    RUN_VSP_FULL_EXT_YYYYmmdd_HHMMSS

    Trả về ISO string 'YYYY-MM-DDTHH:MM:SS' hoặc None.
    """
    parts = run_id.split("_")
    if len(parts) < 3:
        return None

    date_str = parts[-2]
    time_str = parts[-1]
    try:
        dt = datetime.strptime(date_str + time_str, "%Y%m%d%H%M%S")
        # Không cần timezone, giữ local string
        return dt.strftime("%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None


def _parse_profile_from_run_id(run_id: str) -> Optional[str]:
    """
    Từ RUN_VSP_FULL_EXT_20251207_071838 → profile = 'FULL_EXT'
    Tức là bỏ 'RUN' + 'VSP', lấy phần giữa đến trước date/time.
    """
    parts = run_id.split("_")
    if len(parts) <= 3:
        return None

    # Bỏ 'RUN'
    core = parts[1:-2]  # tất cả trừ RUN + date + time
    if not core:
        return None

    # Nếu phần đầu là 'VSP' thì bỏ nó đi cho gọn
    if core[0].upper() == "VSP":
        core = core[1:] or core

    return "_".join(core) if core else None


def _infer_src_from_first_finding(run_dir: Path) -> Optional[str]:
    """
    Đọc findings_unified.json, lấy phần tử đầu, suy src_path từ file path.

    Ví dụ: /home/test/Data/khach6/.scan_unpacked/... → 'khach6'
    """
    f = run_dir / "report" / "findings_unified.json"
    if not f.is_file():
        return None

    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return None

    if isinstance(data, dict) and "items" in data:
        items = data.get("items") or []
    elif isinstance(data, list):
        items = data
    else:
        items = []

    if not items:
        return None

    first = items[0]
    file_path = first.get("file") or ""
    return _infer_src_from_file_path(file_path)


def _infer_src_from_file_path(file_path: str) -> Optional[str]:
    """
    Heuristic:
      - Tìm segment sau '/Data/' → đó là tên src_path (ví dụ 'khach6').
    """
    marker = "/Data/"
    idx = file_path.find(marker)
    if idx == -1:
        return None

    rest = file_path[idx + len(marker) :]
    if not rest:
        return None

    return rest.split("/", 1)[0] or None


def _build_run_entry(run_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Từ 1 thư mục RUN_VSP_FULL_EXT_* build ra object run cho API.
    """
    summary_path = run_dir / "report" / "summary_unified.json"
    summary = _load_json(summary_path)
    if not summary:
        return None

    run_id = summary.get("run_id") or run_dir.name

    # timestamp
    timestamp = summary.get("timestamp") or _parse_timestamp_from_run_id(run_id)

    # profile
    profile = summary.get("profile") or _parse_profile_from_run_id(run_id)

    # src_path – ưu tiên lấy từ summary, fallback từ findings
    src_path = (
        summary.get("src_path")
        or summary.get("src_root")
        or _infer_src_from_first_finding(run_dir)
    )

    # entry_url / target_url
    entry_url = (
        summary.get("entry_url")
        or summary.get("target_url")
        or summary.get("url")
    )

    # các trường cũ
    total_findings = summary.get("total_findings", 0)
    sbom_total = summary.get("sbom_total", 0)
    by_tool = summary.get("by_tool") or {}
    by_severity = summary.get("by_severity") or {}
    security_score = summary.get("security_score", 0)
    top_cwe = summary.get("top_cwe")

    return {
        "run_id": run_id,
        "timestamp": timestamp,
        "profile": profile,
        "src_path": src_path,
        "entry_url": entry_url,
        "total_findings": total_findings,
        "sbom_total": sbom_total,
        "by_tool": by_tool,
        "by_severity": by_severity,
        "security_score": security_score,
        "top_cwe": top_cwe,
    }


@bp_runs.route("/api/vsp/runs_index_v3", methods=["GET"])
def runs_index_v3():
    """
    Trả về ARRAY các run, sort mới nhất trước, với metadata:
    run_id, timestamp, profile, src_path, entry_url, total_findings,
    sbom_total, by_tool, by_severity, security_score, top_cwe
    """
    out_root = _find_out_root()
    if not out_root.is_dir():
        return jsonify([])

    # sort reverse = mới nhất trước
    run_dirs: List[Path] = sorted(
        out_root.glob("RUN_VSP_FULL_EXT_*"),
        reverse=True,
    )

    runs: List[Dict[str, Any]] = []
    for rd in run_dirs:
        entry = _build_run_entry(rd)
        if entry:
            runs.append(entry)

    return jsonify(runs)
