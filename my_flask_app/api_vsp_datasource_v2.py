from flask import Blueprint, jsonify, request
from pathlib import Path
import traceback
import sys
from .common_vsp_latest_run import get_latest_valid_run, load_json

bp = Blueprint("vsp_datasource_api", __name__)


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
