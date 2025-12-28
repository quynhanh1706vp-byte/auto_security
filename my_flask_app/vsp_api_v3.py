from __future__ import annotations

from flask import Blueprint, jsonify, request
from pathlib import Path
import json
from typing import Any, Dict, List, Tuple

# Blueprint chính cho VSP API v3
bp = Blueprint("bp_vsp_v3", __name__)

ROOT = Path(__file__).resolve().parents[2]  # /home/test/Data/SECURITY_BUNDLE
OUT_DIR = ROOT / "out"


# ----------------------------
# Helper: resolve run_id
# ----------------------------
def _resolve_run_id() -> Tuple[str | None, str | None]:
    """
    Trả về (run_id, error).
    - Ưu tiên query param ?run_id
    - Nếu không có, đọc out/last_vsp_run.txt
      + File này có thể là full path hoặc chỉ run_id.
    """
    run_id = (request.args.get("run_id") or "").strip()
    if run_id:
        return run_id, None

    pointer = OUT_DIR / "last_vsp_run.txt"
    if not pointer.is_file():
        return None, "last_vsp_run.txt not found"

    try:
        txt = pointer.read_text(encoding="utf-8").strip()
    except Exception as e:
        return None, f"Cannot read last_vsp_run.txt: {e}"

    if not txt:
        return None, "last_vsp_run.txt is empty"

    p = Path(txt)
    if p.is_dir():
        # /home/test/Data/SECURITY_BUNDLE/out/RUN_...
        return p.name, None

    # Nếu chỉ lưu RUN_VSP_FULL_EXT_...
    return txt, None


def _get_run_dir(run_id: str) -> Path:
    return OUT_DIR / run_id


# ----------------------------
# Helper: load JSON an toàn
# ----------------------------
def _load_json(path: Path) -> Tuple[Any | None, str | None]:
    if not path.is_file():
        return None, f"File not found: {path}"
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f), None
    except Exception as e:
        return None, f"Cannot parse JSON {path}: {e}"


# ----------------------------
# /api/vsp/dashboard_v3
# ----------------------------
@bp.route("/api/vsp/dashboard_v3", methods=["GET"])
def api_vsp_dashboard_v3():
    """
    Dashboard chính – đọc từ report/summary_unified.json của run:
      - ưu tiên ?run_id
      - nếu không truyền thì dùng out/last_vsp_run.txt
    """
    run_id, err = _resolve_run_id()
    if err:
        return jsonify({"ok": False, "error": err}), 500

    run_dir = _get_run_dir(run_id)
    summary_path = run_dir / "report" / "summary_unified.json"

    summary, err = _load_json(summary_path)
    if err:
        return jsonify({"ok": False, "run_id": run_id, "error": err}), 500

    by_severity: Dict[str, int] = summary.get("by_severity") or {}
    by_tool: Dict[str, int] = summary.get("by_tool") or {}

    total_findings = summary.get("total_findings")
    if total_findings is None:
        try:
            total_findings = int(summary.get("total", 0))
        except Exception:
            total_findings = sum(int(v) for v in by_severity.values() if isinstance(v, (int, float)))

    # Tính top_risky_tool (tool có nhiều findings nhất)
    top_risky_tool = None
    if by_tool:
        try:
            top_risky_tool = max(by_tool.items(), key=lambda kv: kv[1])[0]
        except Exception:
            top_risky_tool = None

    # Giữ slot để sau này mapping sang ISO / score thật
    security_score = summary.get("security_score", 0)
    top_cwe = summary.get("top_cwe")
    top_module = summary.get("top_module")

    return jsonify(
        {
            "ok": True,
            "run_id": run_id,
            "total_findings": int(total_findings) if isinstance(total_findings, (int, float)) else 0,
            "by_severity": by_severity,
            "by_tool": by_tool,
            "security_score": security_score,
            "top_risky_tool": top_risky_tool,
            "top_cwe": top_cwe,
            "top_module": top_module,
        }
    )


# ----------------------------
# /api/vsp/datasource_v2
# ----------------------------
@bp.route("/api/vsp/datasource_v2", methods=["GET"])
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

@bp.route("/api/vsp/runs_index_v3", methods=["GET"])
def runs_index_v3():
    from flask import jsonify
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
    runs = sorted(out_dir.glob("RUN_VSP_FULL_EXT_*"), reverse=True)

    items = []
    for r in runs:
        summary_path = r / "report" / "summary_unified.json"
        if not summary_path.is_file():
            continue
        try:
            s = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            continue

        items.append({
            "run_id": s.get("run_id") or r.name,
            "total_findings": s.get("total_findings", 0),
            "sbom_total": s.get("sbom_total", 0),
            "by_tool": s.get("by_tool", {}),
            "by_severity": s.get("by_severity", {}),
            "security_score": s.get("security_score", 0),
            "top_cwe": s.get("top_cwe"),
        })

    return jsonify(items)

@bp.route("/api/vsp/settings_profile_v1", methods=["GET"])
def api_vsp_settings_profile_v1():
    """
    Trả về profile đang dùng cho VSP 2025 – EXT+.
    UI Settings tab đọc chỗ này để show cấu hình.
    """
    data = {
        "ok": True,
        "profile": "EXT+",
        "description": "VersaSecure Platform – VSP 2025 Enterprise Security Profile (EXT+)",
        "tools": [
            "gitleaks",
            "semgrep",
            "kics",
            "codeql",
            "bandit",
            "trivy_fs",
            "grype",
            "syft",
        ],
        "severity_buckets": ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"],
        "notes": [
            "All findings are normalized to 6 DevSecOps levels.",
            "CodeQL chạy đa ngôn ngữ: csharp, javascript, python (và mở rộng sau).",
            "KICS quét Dockerfile / Docker Compose / Terraform / Kubernetes / v.v.",
            "Trivy FS + Grype + Syft cung cấp SBOM + CVE coverage.",
        ],
    }
    return jsonify(data)


# ----------------------------
# /api/vsp/rule_overrides_v1
# ----------------------------
@bp.route("/api/vsp/rule_overrides_v1", methods=["GET"])
def api_vsp_rule_overrides_v1():
    """
    Rule overrides / add / update cho tab Rule Overrides:
    - Nếu có file out/vsp_rule_overrides_v1.json thì đọc.
    - Nếu không, trả về khung trống để UI render.
    """
    overrides_path = OUT_DIR / "vsp_rule_overrides_v1.json"
    if overrides_path.is_file():
        data, err = _load_json(overrides_path)
        if err:
            return jsonify({"ok": False, "error": err}), 500
        return jsonify(data)

    # Khung default
    data = {
        "ok": True,
        "profile": "EXT+",
        "overrides": [],
        "meta": {
            "comment": "No custom overrides yet. All tools run with default EXT+ profile.",
            "examples": [
                {
                    "tool": "semgrep",
                    "rule_id": "sb_aggr_http_endpoint",
                    "action": "lower_severity",
                    "from": "LOW",
                    "to": "INFO",
                    "reason": "Accepted risk for internal-only HTTP endpoints.",
                },
                {
                    "tool": "kics",
                    "rule_id": "1c1325ff-831d-43a1-973e-839ae57dfcc0",
                    "action": "raise_severity",
                    "from": "HIGH",
                    "to": "CRITICAL",
                    "reason": "Sensitive backup-data volumes in production.",
                },
            ],
        },
    }
    return jsonify(data)
