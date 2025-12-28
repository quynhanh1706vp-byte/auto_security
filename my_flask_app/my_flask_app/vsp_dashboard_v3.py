import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from flask import Blueprint, jsonify, current_app

bp_vsp_dashboard_v3 = Blueprint("vsp_dashboard_v3", __name__)

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]
SEVERITY_WEIGHT = {
    "CRITICAL": 10.0,
    "HIGH": 5.0,
    "MEDIUM": 2.0,
    "LOW": 1.0,
    "INFO": 0.2,
    "TRACE": 0.0,
}

def _get_root_dir() -> Path:
    # ROOT = /home/test/Data/SECURITY_BUNDLE
    return Path(__file__).resolve().parents[2]

def _find_latest_run_dir() -> Optional[Path]:
    root = _get_root_dir()
    out_dir = root / "out"
    if not out_dir.is_dir():
        return None
    candidates: List[Tuple[float, Path]] = []
    for p in out_dir.iterdir():
        if p.is_dir() and p.name.startswith("RUN_VSP_FULL_EXT_"):
            try:
                candidates.append((p.stat().st_mtime, p))
            except Exception:
                pass
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]

def _load_findings(run_dir: Optional[Path]) -> Tuple[Optional[str], List[Dict[str, Any]]]:
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
        current_app.logger.exception("[VSP_DASH_V3] Lỗi load findings_unified.json: %s", e)
        return run_dir.name, []

def _norm_sev(val: Any) -> str:
    if not isinstance(val, str):
        return "TRACE"
    v = val.strip().upper()
    return v if v in SEVERITY_ORDER else "TRACE"

def _by_sev(findings: List[Dict[str, Any]]) -> Dict[str, int]:
    counts = {s: 0 for s in SEVERITY_ORDER}
    for f in findings:
        sev = _norm_sev(
            f.get("severity_effective")
            or f.get("severity")
            or f.get("severity_raw")
        )
        if sev in counts:
            counts[sev] += 1
    return counts

def _score(by_sev: Dict[str, int]) -> int:
    if not by_sev:
        return 100
    total_penalty = 0.0
    for sev, count in by_sev.items():
        total_penalty += SEVERITY_WEIGHT.get(sev, 0.0) * count
    score = 100.0 - (total_penalty / 50.0) * 10.0
    score = max(0.0, min(100.0, score))
    return int(round(score))

def _top_tool(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = _norm_sev(f.get("severity_effective") or f.get("severity_raw"))
        if sev not in ("CRITICAL", "HIGH", "MEDIUM"):
            continue
        tool = (f.get("tool") or "").strip()
        if tool:
            ctr[tool] += 1
    return ctr.most_common(1)[0][0] if ctr else "-"

def _top_cwe(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = _norm_sev(f.get("severity_effective") or f.get("severity_raw"))
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
    return ctr.most_common(1)[0][0] if ctr else "-"

def _top_module(findings: List[Dict[str, Any]]) -> str:
    ctr = Counter()
    for f in findings:
        sev = _norm_sev(f.get("severity_effective") or f.get("severity_raw"))
        if sev not in ("CRITICAL", "HIGH", "MEDIUM"):
            continue
        ctx = f.get("code_context") or {}
        module = (f.get("module") or ctx.get("module") or "").strip()
        if module:
            ctr[module] += 1
    return ctr.most_common(1)[0][0] if ctr else "-"

@bp_vsp_dashboard_v3.route("/api/vsp/dashboard_v3", methods=["GET"])
def api_vsp_dashboard_v3():
    """
    TEST OVERRIDE: VSP 2025 – Dashboard v3
    """
    from flask import jsonify

    data = {
        "ok": True,
        "run_id": "RUN_VSP_FULL_EXT_FAKE_TEST_99999999_000000",
        "total_findings": 9999,
        "by_severity": {
            "CRITICAL": 9,
            "HIGH": 99,
            "MEDIUM": 999,
            "LOW": 0,
            "INFO": 0,
            "TRACE": 0
        },
        "top_risky_tool": "override_test_tool"
    }

    return jsonify(data)
@bp_vsp_dashboard_v3.route("/api/vsp/trend_v1", methods=["GET"])
def api_vsp_trend_v1():
    """VSP_P2_TREND_V1_ALLOW_AND_ROBUST_V1B
    Robust trend endpoint: never returns ok:false 'not allowed'.
    Schema: ok, rid_requested, limit, points[{
      label, run_id, total, ts
    }]
    """
    import os, json, datetime
    from flask import request, jsonify

    rid = (request.args.get("rid") or "").strip()
    limit = int(request.args.get("limit") or 20)
    if limit < 5: limit = 5
    if limit > 80: limit = 80

    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
    ]
    roots = [r for r in roots if os.path.isdir(r)]

    def list_run_dirs():
        dirs = []
        for r in roots:
            try:
                for name in os.listdir(r):
                    if not (name.startswith("VSP_") or name.startswith("RUN_")):
                        continue
                    full = os.path.join(r, name)
                    if os.path.isdir(full):
                        try:
                            mt = os.path.getmtime(full)
                        except Exception:
                            mt = 0
                        dirs.append((mt, name, full))
            except Exception:
                pass
        dirs.sort(key=lambda x: x[0], reverse=True)
        return dirs

    def load_json(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return None

    def get_total_from_gate(j):
        if not isinstance(j, dict): return None
        for k in ("total", "total_findings", "findings_total", "total_unified"):
            v = j.get(k)
            if isinstance(v, int): return v
        c = j.get("counts") or j.get("severity_counts") or j.get("by_severity")
        if isinstance(c, dict):
            sm = 0
            for vv in c.values():
                if isinstance(vv, int): sm += vv
            return sm
        return None

    points = []
    for mt, name, d in list_run_dirs()[: max(limit*3, limit) ]:
        gate = load_json(os.path.join(d, "run_gate_summary.json")) or load_json(os.path.join(d, "reports", "run_gate_summary.json"))
        total = get_total_from_gate(gate)
        if total is None:
            fu = load_json(os.path.join(d, "findings_unified.json")) or load_json(os.path.join(d, "reports", "findings_unified.json"))
            if isinstance(fu, list):
                total = len(fu)
            elif isinstance(fu, dict) and isinstance(fu.get("findings"), list):
                total = len(fu.get("findings"))
        if total is None:
            continue

        ts = datetime.datetime.fromtimestamp(mt).isoformat(timespec="seconds")
        label = datetime.datetime.fromtimestamp(mt).strftime("%Y-%m-%d %H:%M")
        points.append({"label": label, "run_id": name, "total": int(total), "ts": ts})
        if len(points) >= limit:
            break

    return jsonify({"ok": True, "rid_requested": rid, "limit": limit, "points": points})

@bp_vsp_dashboard_v3.route("/api/vsp/top_findings_v1", methods=["GET"])
def api_vsp_top_findings_v1():
    run_dir = _get_latest_run_dir()
    if not run_dir:
        return jsonify({"items": []})
    fu_path = run_dir / "report" / "findings_unified.json"
    if not fu_path.exists():
        return jsonify({"items": []})

    with fu_path.open("r", encoding="utf-8") as f:
        findings = _json.load(f)

    high_crit = [
        f for f in findings
        if str(f.get("severity_effective") or f.get("severity") or "").upper()
        in ("CRITICAL", "HIGH")
    ]
    sev_rank = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "INFO": 4, "TRACE": 5}
    high_crit.sort(
        key=lambda x: sev_rank.get(
            str(x.get("severity_effective") or x.get("severity") or "").upper(), 99
        )
    )

    top = []
    for fitem in high_crit[:10]:
        sev = str(fitem.get("severity_effective") or fitem.get("severity") or "")
        tool = fitem.get("tool") or fitem.get("source_tool") or ""
        rule = fitem.get("rule_id") or fitem.get("id") or ""
        file_path = fitem.get("file") or fitem.get("location") or ""
        line = fitem.get("line") or fitem.get("start_line")
        location = f"{file_path}:{line}" if (file_path and line) else file_path
        top.append(
            {"severity": sev, "rule_id": rule, "location": location, "tool": tool}
        )

    return jsonify({"items": top})


@bp_vsp_dashboard_v3.route("/api/vsp/datasource_stats_v1", methods=["GET"])
def api_vsp_datasource_stats_v1():
    """
    Stats cho tab Data Source: by_severity + by_tool
    reuse từ summary_unified của run mới nhất.
    """
    payload = _load_latest_dashboard_payload()
    return jsonify(
        {
            "by_severity": payload.get("by_severity", {}),
            "by_tool": payload.get("by_tool", {}),
        }
    )


def _load_settings():
    if SETTINGS_PATH.exists():
        with SETTINGS_PATH.open("r", encoding="utf-8") as f:
            return _json.load(f)
    return {
        "profile": "default",
        "tools": {
            "semgrep": True,
            "gitleaks": True,
            "bandit": True,
            "trivy_fs": True,
            "grype": True,
            "kics": True,
            "codeql": True,
            "syft": True,
        },
        "limits": {
            "max_findings_per_tool": 5000,
            "top_findings_limit": 10,
        },
    }


@bp_vsp_dashboard_v3.route("/api/vsp/settings/get", methods=["GET"])
def api_vsp_settings_get():
    cfg = _load_settings()
    return jsonify(cfg)


@bp_vsp_dashboard_v3.route("/api/vsp/settings/save", methods=["POST"])
def api_vsp_settings_save():
    payload = request.get_json(force=True) or {}
    with SETTINGS_PATH.open("w", encoding="utf-8") as f:
        _json.dump(payload, f, indent=2, ensure_ascii=False)
    return jsonify({"ok": True})



@bp_vsp_dashboard_v3.route("/api/vsp/datasource_v2", methods=["GET"])
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
