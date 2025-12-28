from __future__ import annotations

import json
import os
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from flask import Flask, render_template, jsonify, request, send_file, abort

# ---- PATHS / CONSTANTS ----

UI_DIR = Path(__file__).resolve().parent
ROOT = UI_DIR.parent
OUT_DIR = ROOT / "out"

app = Flask(__name__)


# ---- HELPERS ----

def _safe_read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        if not path.is_file():
            return None
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None


def _discover_run_dirs(limit: int = 50) -> List[Path]:
    """
    Tìm các thư mục RUN_* trong out/ (mới nhất trước).
    """
    if not OUT_DIR.is_dir():
        return []
    runs = [p for p in OUT_DIR.iterdir() if p.is_dir() and p.name.startswith("RUN_")]
    runs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return runs[:limit]


def _load_summary(run_dir: Path) -> Optional[Dict[str, Any]]:
    return _safe_read_json(run_dir / "report" / "summary_unified.json")


def _load_findings(run_dir: Path) -> Optional[List[Dict[str, Any]]]:
    data = _safe_read_json(run_dir / "report" / "findings_unified.json")
    if isinstance(data, list):
        return data
    if isinstance(data, dict) and "items" in data and isinstance(data["items"], list):
        return data["items"]
    return None


def _get_latest_run() -> Optional[Path]:
    """
    Ưu tiên RUN_* có findings_unified.json khác rỗng.
    Nếu không có, fallback sang RUN_* có summary_unified.json.
    """
    candidates = _discover_run_dirs(limit=50)
    best_run = None

    # ưu tiên có findings_unified.json
    for run_dir in candidates:
        findings_path = run_dir / "report" / "findings_unified.json"
        if findings_path.is_file() and findings_path.stat().st_size > 0:
            best_run = run_dir
            break

    if best_run:
        return best_run

    # fallback: có summary_unified.json
    for run_dir in candidates:
        if (run_dir / "report" / "summary_unified.json").is_file():
            return run_dir

    return None


def _extract_ts(summary: Dict[str, Any], run_dir: Path) -> str:
    for key in ("ts", "timestamp", "time"):
        if key in summary and isinstance(summary[key], str):
            return summary[key]
    # fallback: lấy từ mtime thư mục
    mtime = datetime.fromtimestamp(run_dir.stat().st_mtime)
    return mtime.isoformat()


def _build_severity(summary: Dict[str, Any]) -> Dict[str, int]:
    sev = summary.get("by_severity") or summary.get("severity") or {}
    return {
        "CRITICAL": int(sev.get("CRITICAL", 0)),
        "HIGH": int(sev.get("HIGH", 0)),
        "MEDIUM": int(sev.get("MEDIUM", 0)),
        "LOW": int(sev.get("LOW", 0)),
        "INFO": int(sev.get("INFO", 0)),
        "TRACE": int(sev.get("TRACE", 0)),
    }


def _build_by_tool(summary: Dict[str, Any]) -> Dict[str, int]:
    bt = summary.get("by_tool") or {}
    return {k: int(v) for k, v in bt.items()}


# ---- UI ROUTE ----

@app.route("/security_bundle")
def vsp_index():
    return render_template("vsp_index.html")


# ---- API: RUN FULL SCAN ----

@app.route("/api/vsp/run", methods=["POST"])
def api_vsp_run():
    """
    POST /api/vsp/run
    Body:
    {
      "src_path": "/home/test/Data/khach6",
      "profile": "EXT",
      "level": "EXT",
      "no_net": 0
    }

    Hiện tại: gọi bin/run_vsp_full_ext.sh (nếu tồn tại),
    sau đó lấy RUN_ mới nhất và trả summary.
    """
    payload = request.get_json(silent=True) or {}
    src_path = payload.get("src_path") or "/home/test/Data/khach6"
    profile = payload.get("profile") or "EXT"
    level = payload.get("level") or "EXT"
    no_net = int(payload.get("no_net", 0))

    script = ROOT / "bin" / "run_vsp_full_ext.sh"
    if not script.is_file():
        return jsonify(
            {
                "status": "error",
                "message": f"Script {script} not found.",
            }
        ), 500

    env = os.environ.copy()
    # Cho phép script dùng biến env nếu muốn
    env["VSP_SRC_PATH"] = src_path
    env["VSP_PROFILE"] = profile
    env["VSP_LEVEL"] = level
    env["VSP_NO_NET"] = str(no_net)

    try:
        # NOTE: giả định script chạy sync, sinh RUN_ mới trong out/
        subprocess.run(
            [str(script)],
            cwd=str(ROOT),
            env=env,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except subprocess.CalledProcessError as e:
        return jsonify(
            {
                "status": "error",
                "message": "run_vsp_full_ext.sh failed",
                "stdout": e.stdout,
                "stderr": e.stderr,
            }
        ), 500

    run_dir = _get_latest_run()
    if not run_dir:
        return jsonify(
            {
                "status": "error",
                "message": "No RUN_ directory found after scan.",
            }
        ), 500

    summary = _load_summary(run_dir) or {}
    severity = _build_severity(summary)
    by_tool = _build_by_tool(summary)
    total_findings = int(summary.get("total_findings", sum(severity.values())))
    run_id = run_dir.name
    ts = _extract_ts(summary, run_dir)

    return jsonify(
        {
            "status": "ok",
            "run_id": run_id,
            "run_dir": str(run_dir.relative_to(ROOT)),
            "summary": {
                "total_findings": total_findings,
                "by_severity": severity,
                "by_tool": by_tool,
            },
            "ts": ts,
        }
    )


# ---- API: DASHBOARD (LAST RUN) ----

@app.route("/api/vsp/dashboard")
def api_vsp_dashboard():
    """
    GET /api/vsp/dashboard

    Đọc LAST_RUN -> summary_unified.json
    Trả:
    {
      "severity": {...},
      "total_findings": ...,
      "by_tool": {...},
      "run_id": "...",
      "ts": "...",
      "extra_charts": { "trend": [...] }
    }
    """
    run_dir = _get_latest_run()
    if not run_dir:
        return jsonify(
            {
                "ok": False,
                "message": "No runs found.",
                "severity": {},
                "total_findings": 0,
                "by_tool": {},
                "run_id": None,
                "ts": None,
                "extra_charts": {},
            }
        )

    summary = _load_summary(run_dir) or {}
    severity = _build_severity(summary)
    by_tool = _build_by_tool(summary)
    total_findings = int(summary.get("total_findings", sum(severity.values())))
    run_id = run_dir.name
    ts = _extract_ts(summary, run_dir)

    # trend: duyệt nhiều RUN_ và lấy total_findings
    trend_rows: List[Dict[str, Any]] = []
    for rd in reversed(_discover_run_dirs(limit=12)):  # cũ -> mới
        s = _load_summary(rd)
        if not s:
            continue
        sev_tmp = _build_severity(s)
        total_tmp = int(s.get("total_findings", sum(sev_tmp.values())))
        trend_rows.append(
            {
                "run_id": rd.name,
                "ts": _extract_ts(s, rd),
                "total_findings": total_tmp,
            }
        )

    return jsonify(
        {
            "ok": True,
            "severity": severity,
            "total_findings": total_findings,
            "by_tool": by_tool,
            "run_id": run_id,
            "ts": ts,
            "extra_charts": {"trend": trend_rows},
        }
    )


# ---- API: DATA SOURCE (FINDINGS TABLE) ----

@app.route("/api/vsp/datasource")
def api_vsp_datasource():
    """
    GET /api/vsp/datasource?severity=&tool=&limit=&offset=&search=

    Đọc findings_unified.json của LAST_RUN.
    """
    run_dir = _get_latest_run()
    if not run_dir:
        return jsonify(
            {
                "run_id": None,
                "total": 0,
                "items": [],
            }
        )

    findings = _load_findings(run_dir) or []
    tool = request.args.get("tool", "").strip()
    severity = request.args.get("severity", "").strip()
    search = request.args.get("search", "").strip().lower()

    try:
        limit = int(request.args.get("limit", "200"))
    except ValueError:
        limit = 200
    try:
        offset = int(request.args.get("offset", "0"))
    except ValueError:
        offset = 0

    def match_item(it: Dict[str, Any]) -> bool:
        if tool and it.get("tool") != tool:
            return False
        if severity and it.get("severity") != severity:
            return False
        if search:
            text_parts = [
                str(it.get("message", "")),
                str(it.get("file", "")),
                str(it.get("rule_id", "")),
            ]
            if search not in " ".join(text_parts).lower():
                return False
        return True

    filtered = [it for it in findings if match_item(it)]
    total = len(filtered)
    slice_items = filtered[offset : offset + limit]

    # đảm bảo mỗi item có id tăng dần (nếu chưa có)
    for idx, it in enumerate(slice_items, start=offset + 1):
        if "id" not in it:
            it["id"] = idx

    return jsonify(
        {
            "run_id": run_dir.name,
            "total": total,
            "items": slice_items,
        }
    )


# ---- API: RUNS HISTORY ----

@app.route("/api/vsp/runs")
def api_vsp_runs():
    """
    GET /api/vsp/runs

    Trả danh sách RUN_* (mới -> cũ).
    """
    runs_info: List[Dict[str, Any]] = []
    for run_dir in _discover_run_dirs(limit=50):
        summary = _load_summary(run_dir)
        if not summary:
            continue
        sev = _build_severity(summary)
        total = int(summary.get("total_findings", sum(sev.values())))
        runs_info.append(
            {
                "run_id": run_dir.name,
                "ts": _extract_ts(summary, run_dir),
                "total_findings": total,
                "by_severity": sev,
            }
        )
    return jsonify(runs_info)


@app.route("/api/vsp/run/<run_id>/summary")
def api_vsp_run_summary(run_id: str):
    """
    GET /api/vsp/run/<run_id>/summary
    """
    run_dir = OUT_DIR / run_id
    if not run_dir.is_dir():
        return jsonify({"error": "run_id not found"}), 404

    summary = _load_summary(run_dir)
    if not summary:
        return jsonify({"error": "summary_unified.json not found"}), 404

    sev = _build_severity(summary)
    bt = _build_by_tool(summary)
    total = int(summary.get("total_findings", sum(sev.values())))
    ts = _extract_ts(summary, run_dir)
    profile = summary.get("profile", "EXT")

    return jsonify(
        {
            "run_id": run_id,
            "ts": ts,
            "profile": profile,
            "total_findings": total,
            "by_severity": sev,
            "by_tool": bt,
        }
    )


@app.route("/api/vsp/run/<run_id>/report/html")
def api_vsp_run_report_html(run_id: str):
    """
    GET /api/vsp/run/<run_id>/report/html

    Cố gắng trả file HTML report nếu có,
    nếu không thì trả HTML đơn giản từ summary.
    """
    run_dir = OUT_DIR / run_id
    if not run_dir.is_dir():
        abort(404)

    # thử các tên file phổ biến
    candidates = [
        run_dir / "report" / "report.html",
        run_dir / "report" / "vsp_report.html",
        run_dir / "report" / "checkmarx_like.html",
    ]
    for p in candidates:
        if p.is_file():
            return send_file(str(p), mimetype="text/html")

    summary = _load_summary(run_dir)
    if not summary:
        abort(404)

    sev = _build_severity(summary)
    bt = _build_by_tool(summary)
    total = int(summary.get("total_findings", sum(sev.values())))
    ts = _extract_ts(summary, run_dir)

    # HTML đơn giản
    html = [
        "<!doctype html>",
        "<html><head><meta charset='utf-8'><title>VSP Report</title>",
        "<style>body{font-family:system-ui, sans-serif;padding:20px;background:#0b1020;color:#e5e7eb;}table{border-collapse:collapse;width:100%;margin-top:16px;}th,td{border:1px solid #1f2937;padding:4px 6px;font-size:12px;}th{background:#111827;}</style>",
        "</head><body>",
        f"<h2>VSP Report – {run_id}</h2>",
        f"<p>Timestamp: {ts}</p>",
        f"<p>Total findings: {total}</p>",
        "<h3>By severity</h3>",
        "<table><tbody>",
    ]
    for k, v in sev.items():
        html.append(f"<tr><td>{k}</td><td>{v}</td></tr>")
    html.append("</tbody></table>")

    html.append("<h3>By tool</h3><table><tbody>")
    for k, v in bt.items():
        html.append(f"<tr><td>{k}</td><td>{v}</td></tr>")
    html.append("</tbody></table>")

    html.append("</body></html>")
    return html[0] + "".join(html[1:])


# ---- API: SETTINGS ----

@app.route("/api/vsp/settings")
def api_vsp_settings():
    """
    GET /api/vsp/settings

    Trả:
    {
      "profile": "EXT",
      "src_path": "/home/test/Data/khach6",
      "last_run_id": "...",
      "ts_last_run": "...",
      "tools": {
        "gitleaks": true,
        ...
      }
    }
    """
    # Profile & SRC: có thể sau này đọc từ file config riêng.
    profile = "EXT"
    src_path = os.environ.get("VSP_DEFAULT_SRC", "/home/test/Data/khach6")

    run_dir = _get_latest_run()
    last_run_id = run_dir.name if run_dir else None
    ts_last_run = None
    if run_dir:
        s = _load_summary(run_dir) or {}
        ts_last_run = _extract_ts(s, run_dir)

    tools = {
        "gitleaks": True,
        "semgrep": True,
        "kics": True,
        "codeql": True,
        "bandit": True,
        "trivy_fs": True,
        "syft": True,
        "grype": True,
    }

    return jsonify(
        {
            "profile": profile,
            "src_path": src_path,
            "last_run_id": last_run_id,
            "ts_last_run": ts_last_run,
            "tools": tools,
        }
    )


if __name__ == "__main__":
    # Chạy dev trên 0.0.0.0:8910 giống trước đây
    app.run(host="0.0.0.0", port=8910)

@app.route("/")
def root():
    return render_template("vsp_index.html")

@app.route("/")
def root():
    return render_template("vsp_index.html")
