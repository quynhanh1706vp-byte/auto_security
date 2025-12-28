from __future__ import annotations
import json
import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import Flask, jsonify, render_template, send_from_directory, request

# === VSP_KICS_TAIL_HELPERS_V2 ===
import json as _vsp_json
from pathlib import Path as _vsp_Path

def _vsp_safe_tail_text(_p, max_bytes=8192, max_lines=120):
    try:
        _p = _vsp_Path(_p)
        if not _p.exists():
            return ""
        b = _p.read_bytes()
    except Exception:
        return ""
    if max_bytes and len(b) > max_bytes:
        b = b[-max_bytes:]
    try:
        s = b.decode("utf-8", errors="replace")
    except Exception:
        s = str(b)
    lines = s.splitlines()
    if max_lines and len(lines) > max_lines:
        lines = lines[-max_lines:]
    return "\n".join(lines).strip()

def _vsp_kics_tail_from_ci(ci_run_dir):
    if not ci_run_dir:
        return ""
    try:
        base = _vsp_Path(str(ci_run_dir))
    except Exception:
        return ""
    klog = base / "kics" / "kics.log"
    if klog.exists():
        return _vsp_safe_tail_text(klog)

    djson = base / "degraded_tools.json"
    if djson.exists():
        try:
            raw = djson.read_text(encoding="utf-8", errors="ignore").strip() or "[]"
            data = _vsp_json.loads(raw)
            items = data.get("degraded_tools", []) if isinstance(data, dict) else data
            for it in (items or []):
                tool = str((it or {}).get("tool","")).upper()
                if tool == "KICS":
                    rc = (it or {}).get("rc")
                    reason = (it or {}).get("reason") or (it or {}).get("msg") or "degraded"
                    return "MISSING_TOOL: KICS (rc=%s) reason=%s" % (rc, reason)
        except Exception:
            pass

    if (base / "kics").exists():
        return "NO_KICS_LOG: %s" % (klog,)
    return ""
# === END VSP_KICS_TAIL_HELPERS_V2 ===

# === VSP_KICS_TAIL_HELPERS_V1 ===
import json as _vsp_json
from pathlib import Path as _vsp_Path

def _vsp_safe_tail_text(_p, max_bytes=8192, max_lines=120):
    try:
        _p = _vsp_Path(_p)
        if not _p.exists():
            return ""
        b = _p.read_bytes()
    except Exception:
        return ""
    if max_bytes and len(b) > max_bytes:
        b = b[-max_bytes:]
    try:
        s = b.decode("utf-8", errors="replace")
    except Exception:
        s = str(b)
    lines = s.splitlines()
    if max_lines and len(lines) > max_lines:
        lines = lines[-max_lines:]
    return "\n".join(lines).strip()

def _vsp_kics_tail_from_ci(ci_run_dir):
    if not ci_run_dir:
        return ""
    try:
        base = _vsp_Path(str(ci_run_dir))
    except Exception:
        return ""
    klog = base / "kics" / "kics.log"
    if klog.exists():
        t = _vsp_safe_tail_text(klog)
        return t if isinstance(t, str) else str(t)

    # degrade/missing tool hint
    djson = base / "degraded_tools.json"
    if djson.exists():
        try:
            raw = djson.read_text(encoding="utf-8", errors="ignore").strip() or "[]"
            data = _vsp_json.loads(raw)
            items = data.get("degraded_tools", []) if isinstance(data, dict) else data
            for it in (items or []):
                tool = str((it or {}).get("tool","")).upper()
                if tool == "KICS":
                    rc = (it or {}).get("rc")
                    reason = (it or {}).get("reason") or (it or {}).get("msg") or "degraded"
                    return "MISSING_TOOL: KICS (rc=%s) reason=%s" % (rc, reason)
        except Exception:
            pass

    if (base / "kics").exists():
        return "NO_KICS_LOG: %s" % (klog,)
    return ""
# === END VSP_KICS_TAIL_HELPERS_V1 ===

# ---- Paths ----
HERE = Path(__file__).resolve().parent          # ui/
ROOT = HERE.parent                              # SECURITY_BUNDLE/
OUT_ROOT = ROOT / "out"

app = Flask(
    __name__,
    static_folder=str(HERE / "my_flask_app" / "static"),
    template_folder=str(HERE / "my_flask_app" / "templates"),
)

# -------------------------------------------------
# Helper
# -------------------------------------------------
def _load_json(path: Path, default: Any) -> Any:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _discover_run_dirs(limit: int = 50) -> List[Path]:
    if not OUT_ROOT.exists():
        return []
    dirs: List[Path] = []
    for p in OUT_ROOT.iterdir():
        if p.is_dir() and p.name.startswith("RUN_"):
            dirs.append(p)
    dirs.sort(key=lambda p: p.name, reverse=True)
    return dirs[:limit]


def _get_latest_run() -> Optional[Path]:
    runs = _discover_run_dirs(limit=1)
    return runs[0] if runs else None


def _summary_for_run(run_dir: Path) -> Dict[str, Any]:
    summary_path = run_dir / "report" / "summary_unified.json"
    return _load_json(summary_path, {})


def _findings_for_run(run_dir: Path) -> List[Dict[str, Any]]:
    # findings_unified.json do SECURITY_BUNDLE tạo
    path = run_dir / "report" / "findings_unified.json"
    return _load_json(path, [])


# -------------------------------------------------
# UI
# -------------------------------------------------
@app.route("/security_bundle")
def vsp_index():
    return render_template("index.html")


# -------------------------------------------------
# TAB 1 – DASHBOARD (giữ nguyên – đọc từ summary_unified.json mới nhất)
# -------------------------------------------------
@app.route("/api/vsp/dashboard")
def api_vsp_dashboard() -> Any:
    run_dir = _get_latest_run()
    if not run_dir:
        return jsonify({"ok": False, "reason": "no_runs"}), 200

    summary = _summary_for_run(run_dir)
    sev = summary.get("severity_counts", {})
    tool_counts = summary.get("tool_counts", {})
    meta = summary.get("meta", {})

    total = summary.get("total_findings")
    if total is None and isinstance(sev, dict):
        total = sum(int(sev.get(k, 0)) for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"])

    data = {
        "ok": True,
        "run_id": run_dir.name,
        "meta": {
            "ts": meta.get("ts", ""),
            "src_path": meta.get("src_path", ""),
            "profile": meta.get("profile", "EXT+ / Offline"),
            "engine_mode": meta.get("engine_mode", "offline"),
        },
        "kpi": {
            "total_findings": total or 0,
            "severity": {
                "CRITICAL": sev.get("CRITICAL", 0),
                "HIGH": sev.get("HIGH", 0),
                "MEDIUM": sev.get("MEDIUM", 0),
                "LOW": sev.get("LOW", 0),
                "INFO": sev.get("INFO", 0),
                "TRACE": sev.get("TRACE", 0),
            },
            "tool_counts": tool_counts,
        },
    }
    return jsonify(data)


# -------------------------------------------------
# TAB 2 – RUNS & REPORTS
# -------------------------------------------------
@app.route("/api/vsp/runs_index")
def api_vsp_runs_index() -> Any:
    runs_info: List[Dict[str, Any]] = []

    for run_dir in _discover_run_dirs(limit=50):
        summary = _summary_for_run(run_dir)
        sev = summary.get("severity_counts", {}) or {}
        meta = summary.get("meta", {}) or {}
        tool_counts = summary.get("tool_counts", {}) or {}

        total = summary.get("total_findings")
        if total is None and isinstance(sev, dict):
            total = sum(int(sev.get(k, 0)) for k in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"])

        runs_info.append(
            {
                "run_id": run_dir.name,
                "ts": meta.get("ts", ""),
                "src_path": meta.get("src_path", ""),
                "profile": meta.get("profile", "EXT+ / Offline"),
                "engine_mode": meta.get("engine_mode", "offline"),
                "total_findings": total or 0,
                "severity": {
                    "CRITICAL": sev.get("CRITICAL", 0),
                    "HIGH": sev.get("HIGH", 0),
                    "MEDIUM": sev.get("MEDIUM", 0),
                    "LOW": sev.get("LOW", 0),
                    "INFO": sev.get("INFO", 0),
                    "TRACE": sev.get("TRACE", 0),
                },
                "tools": sorted(tool_counts.keys()),
                # route report html/pdf – bạn có thể map sang đúng path nếu khác
                "report_html": f"/out/{run_dir.name}/report/report.html",
                "report_pdf": f"/out/{run_dir.name}/report/report.pdf",
            }
        )

    return jsonify({"ok": True, "runs": runs_info})


# -------------------------------------------------
# TAB 3 – DATA SOURCE (table findings_unified)
# -------------------------------------------------
@app.route("/api/vsp/datasource")
def api_vsp_datasource() -> Any:
    run_id = request.args.get("run_id")
    if run_id:
        run_dir = OUT_ROOT / run_id
        if not run_dir.exists():
            return jsonify({"ok": False, "reason": "run_not_found"}), 200
    else:
        run_dir = _get_latest_run()
        if not run_dir:
            return jsonify({"ok": False, "reason": "no_runs"}), 200

    findings = _findings_for_run(run_dir)

    rows: List[Dict[str, Any]] = []
    for i, f in enumerate(findings[:300]):  # giới hạn 300 dòng cho UI
        rows.append(
            {
                "idx": i + 1,
                "tool": f.get("tool", ""),
                "severity": f.get("severity", ""),
                "file": f.get("file", ""),
                "line": f.get("line", ""),
                "rule_id": f.get("rule_id") or f.get("check_id") or "",
                "title": f.get("title") or f.get("message") or "",
                "cwe": f.get("cwe") or "",
                "cve": f.get("cve") or "",
            }
        )

    return jsonify(
        {
            "ok": True,
            "run_id": run_dir.name,
            "rows": rows,
            "total_rows": len(findings),
        }
    )


# -------------------------------------------------
# TAB 4 – SETTINGS (cấu hình engine hiện tại)
# -------------------------------------------------
@app.route("/api/vsp/settings")
def api_vsp_settings() -> Any:
    run_dir = _get_latest_run()
    meta: Dict[str, Any] = {}
    tools: List[str] = []

    if run_dir:
        summary = _summary_for_run(run_dir)
        meta = summary.get("meta", {}) or {}
        tool_counts = summary.get("tool_counts", {}) or {}
        tools = sorted(tool_counts.keys())

    settings = {
        "ok": True,
        "profile_label": "EXT+ – Multi-tool / Offline",
        "src_path": meta.get("src_path", ""),
        "engine_mode": meta.get("engine_mode", "offline"),
        "last_run_id": run_dir.name if run_dir else "",
        "tools_enabled": tools,
    }
    return jsonify(settings)


# -------------------------------------------------
# TAB 5 – RULE OVERRIDES (đọc từ rules/vsp_rule_overrides.json nếu có)
# -------------------------------------------------
@app.route("/api/vsp/rule_overrides")
def api_vsp_rule_overrides() -> Any:
    rules_path = ROOT / "rules" / "vsp_rule_overrides.json"
    raw = _load_json(rules_path, [])

    rows: List[Dict[str, Any]] = []
    if isinstance(raw, dict):
        raw = raw.get("rules", [])

    for r in raw or []:
        rows.append(
            {
                "tool": r.get("tool", ""),
                "rule_id": r.get("rule_id", ""),
                "match": r.get("match", ""),
                "action": r.get("action", ""),
                "note": r.get("note", ""),
            }
        )

    return jsonify({"ok": True, "rules": rows})


# -------------------------------------------------
# Static report helper (optional)
# -------------------------------------------------
@app.route("/out/<path:path>")
def serve_out(path: str):
    return send_from_directory(str(OUT_ROOT), path)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8910, debug=True)


# === VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2 ===
def _vsp__inject_kics_tail_to_response(resp):
    try:
        from flask import request as _req
        import json as _json

        path = (_req.path or "")
        if not path.startswith("/api/vsp/run_status_v1/"):
            return resp

        # try flask response json first
        obj = None
        try:
            obj = resp.get_json(silent=True)
        except Exception:
            obj = None

        if obj is None:
            raw = resp.get_data(as_text=True) or ""
            if not raw.strip():
                return resp
            try:
                obj = _json.loads(raw)
            except Exception:
                return resp

        if not isinstance(obj, dict):
            return resp

        if "kics_tail" not in obj:
            ci = obj.get("ci_run_dir") or obj.get("ci_dir") or obj.get("ci_run") or ""
            kt = _vsp_kics_tail_from_ci(ci) if ci else ""
            obj["kics_tail"] = kt if isinstance(kt, str) else str(kt)
        else:
            kt = obj.get("kics_tail")
            if kt is None:
                obj["kics_tail"] = ""
            elif not isinstance(kt, str):
                obj["kics_tail"] = str(kt)

        obj.setdefault("_handler", "after_request_inject:/api/vsp/run_status_v1")

        resp.set_data(_json.dumps(obj, ensure_ascii=False))
        resp.mimetype = "application/json"
        return resp
    except Exception:
        return resp

# bind to app if present
try:
    @app.after_request
    def __vsp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass

# bind to bp if module uses blueprint
try:
    @bp.after_request
    def __vsp_bp_after_request_kics_tail_v2(resp):
        return _vsp__inject_kics_tail_to_response(resp)
except Exception:
    pass
# === END VSP_AFTER_REQUEST_INJECT_KICS_TAIL_V2 ===

