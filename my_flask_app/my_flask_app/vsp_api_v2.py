import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from flask import Blueprint, current_app, jsonify, request

bp_vsp_v2 = Blueprint("vsp_v2", __name__)

# ===== Helpers: tìm RUN_VSP_FULL_EXT_* mới nhất =====

def get_root_dir() -> Path:
    # ROOT = /home/test/Data/SECURITY_BUNDLE
    return Path(__file__).resolve().parents[2]


def find_latest_vsp_run_dir() -> Optional[Path]:
    root = get_root_dir()
    out_dir = root / "out"
    if not out_dir.is_dir():
        return None

    candidates: List[Tuple[float, Path]] = []
    for p in out_dir.iterdir():
        if not p.is_dir():
            continue
        if not p.name.startswith("RUN_VSP_FULL_EXT_"):
            continue
        try:
            candidates.append((p.stat().st_mtime, p))
        except Exception:
            continue

    if not candidates:
        return None

    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def load_findings_unified(run_dir: Optional[Path] = None) -> Tuple[Optional[str], List[Dict[str, Any]]]:
    if run_dir is None:
        run_dir = find_latest_vsp_run_dir()

    if run_dir is None:
        return None, []

    report_dir = run_dir / "report"
    findings_path = report_dir / "findings_unified.json"
    if not findings_path.is_file():
        return run_dir.name, []

    try:
        data = json.loads(findings_path.read_text(encoding="utf-8"))
        if isinstance(data, list):
            return run_dir.name, data
        if isinstance(data, dict) and isinstance(data.get("items"), list):
            return run_dir.name, data["items"]
        return run_dir.name, []
    except Exception as e:
        current_app.logger.exception("[VSP_V2] Lỗi load findings_unified.json: %s", e)
        return run_dir.name, []


# ===== Severity helpers =====

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]
SEVERITY_WEIGHT = {
    "CRITICAL": 10.0,
    "HIGH": 5.0,
    "MEDIUM": 2.0,
    "LOW": 1.0,
    "INFO": 0.2,
    "TRACE": 0.0,
}


def normalize_severity(value: Any) -> str:
    if not isinstance(value, str):
        return "TRACE"
    val = value.strip().upper()
    if val in SEVERITY_ORDER:
        return val
    return "TRACE"


def compute_by_severity(findings: List[Dict[str, Any]]) -> Dict[str, int]:
    counts = {sev: 0 for sev in SEVERITY_ORDER}
    for f in findings:
        sev = normalize_severity(
            f.get("severity_effective")
            or f.get("severity")
            or f.get("severity_raw")
        )
        if sev in counts:
            counts[sev] += 1
    return counts


def compute_security_score(by_sev: Dict[str, int]) -> int:
    """
    Score đơn giản:
    - Base = 100
    - Trừ điểm theo weighted sum từng severity.
    - 0 <= score <= 100
    """
    if not by_sev:
        return 100

    total_penalty = 0.0
    for sev, count in by_sev.items():
        total_penalty += SEVERITY_WEIGHT.get(sev, 0.0) * count

    # Scale: mỗi 50 penalty trừ 10 điểm
    score = 100.0 - (total_penalty / 50.0) * 10.0
    score = max(0.0, min(100.0, score))
    return int(round(score))


def _get_field(f: Dict[str, Any], *keys: str) -> Any:
    cur: Any = f
    for k in keys:
        if cur is None:
            return None
        if isinstance(cur, dict):
            cur = cur.get(k)
        else:
            return None
    return cur


# ===== Top risky tool / cwe / module =====

def compute_top_risky_tool(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = normalize_severity(f.get("severity_effective") or f.get("severity_raw"))
        if sev not in ("CRITICAL", "HIGH", "MEDIUM"):
            continue
        tool = (f.get("tool") or "").strip()
        if tool:
            ctr[tool] += 1
    if not ctr:
        return "-"
    return ctr.most_common(1)[0][0]


def compute_top_cwe(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = normalize_severity(f.get("severity_effective") or f.get("severity_raw"))
        if sev not in ("CRITICAL", "HIGH", "MEDIUM"):
            continue

        vuln = f.get("vuln") or {}
        extra = f.get("extra") or {}

        cwe_ids = vuln.get("cwe_ids")
        if isinstance(cwe_ids, list):
            for c in cwe_ids:
                if isinstance(c, str) and c.strip():
                    ctr[c.strip()] += 1
            continue

        cwe_id = vuln.get("cwe_id") or extra.get("cwe_id") or extra.get("cwe")
        if isinstance(cwe_id, str) and cwe_id.strip():
            ctr[cwe_id.strip()] += 1

    if not ctr:
        return "-"
    return ctr.most_common(1)[0][0]


def compute_top_module(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = normalize_severity(f.get("severity_effective") or f.get("severity_raw"))
        if sev not in ("CRITICAL", "HIGH", "MEDIUM"):
            continue

        module = (
            (f.get("module") or "") 
            or (_get_field(f, "code_context", "module") or "")
        ).strip()

        if module:
            ctr[module] += 1

    if not ctr:
        return "-"
    return ctr.most_common(1)[0][0]


# ===== /api/vsp/datasource_v2 =====

# [VSP][CLEANUP] disabled duplicate datasource_v2 route
# @bp_vsp_v2.route("/api/vsp/datasource_v2", methods=["GET"])
def datasource_v2():
    from flask import request, jsonify
    from pathlib import Path
    import json

    cur = Path(__file__).resolve()
    ROOT = None
    for p in cur.parents:
        if (p / "out").is_dir():
            ROOT = p
            break
    if ROOT is None:
        ROOT = cur.parents[1]
    out_dir = ROOT / "out"

    run_dir = request.args.get("run_dir", "").strip()
    limit = request.args.get("limit", "").strip()
    offset = request.args.get("offset", "").strip()

    try:
        limit_val = int(limit) if limit else None
    except ValueError:
        limit_val = None
    try:
        offset_val = int(offset) if offset else 0
    except ValueError:
        offset_val = 0

    if run_dir:
        run_path = Path(run_dir)
    else:
        runs = sorted(out_dir.glob("RUN_VSP_FULL_EXT_*"), reverse=True)
        if not runs:
            return jsonify(ok=False, error="No runs found")
        run_path = runs[0]

    findings_path = run_path / "report" / "findings_unified.json"
    if not findings_path.is_file():
        return jsonify(ok=False, error=f"findings_unified.json not found for {run_path}")

    try:
        data = json.loads(findings_path.read_text(encoding="utf-8"))
    except Exception as e:
        return jsonify(ok=False, error=f"Parse error: {e}")

    # Hỗ trợ cả dạng list và dạng { "items": [...] }
    if isinstance(data, list):
        items = data
    elif isinstance(data, dict):
        items = data.get("items") or []
    else:
        items = []

    # Enrich từng finding với module / fix / tags
    def enrich_finding(f):
        try:
            f = dict(f)
        except Exception:
            return f

        file_path = str(f.get("file", ""))
        tool = str(f.get("tool", "")).lower()
        cwe = f.get("cwe")

        module = ""
        src_root = ""

        p = file_path
        idx = p.find("/Data/")
        if idx >= 0:
            suffix = p[idx + len("/Data/"):]
        else:
            suffix = p

        parts = [seg for seg in suffix.split("/") if seg]
        if parts:
            src_root = parts[0]
        if len(parts) > 2:
            module = "/".join(parts[1:3])
        elif len(parts) > 1:
            module = parts[1]

        tags = []
        if tool in ("gitleaks",):
            tags.append("secrets")
        if tool in ("grype", "trivy_fs", "syft", "kics"):
            tags.append("deps")
        if tool in ("bandit", "semgrep", "codeql"):
            tags.append("code")
        if cwe and str(cwe).upper() != "UNKNOWN":
            tags.append(str(cwe))
        if not tags:
            tags.append("general")

        f.setdefault("src_path", src_root)
        f.setdefault("module", module)

        msg = f.get("fix") or f.get("recommendation") or f.get("message") or ""
        msg = str(msg)
        max_len = 140
        if len(msg) > max_len:
            msg = msg[: max_len - 1] + "…"
        f["fix"] = msg
        f["tags"] = tags

        return f

    items = [enrich_finding(f) for f in items]

    total = len(items)
    start = offset_val if offset_val >= 0 else 0
    end = start + limit_val if (limit_val is not None and limit_val > 0) else total
    sliced = items[start:end]

    return jsonify(
        ok=True,
        items=sliced,
        count=total,
        limit=limit_val,
        offset=offset_val,
        run_dir=str(run_path),
    )
