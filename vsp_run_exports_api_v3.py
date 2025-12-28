from flask import Blueprint, request, abort, send_file, make_response
from pathlib import Path
import json
import csv
import io
import datetime as dt

vsp_exports_bp = Blueprint("vsp_exports_v3", __name__)

ROOT_DIR = Path(__file__).resolve().parents[1]  # /home/test/Data/SECURITY_BUNDLE
OUT_DIR = ROOT_DIR / "out"


def _find_run_dir(run_id: str) -> Path | None:
    """Tìm thư mục run trong OUT_DIR."""
    if not run_id:
        return None
    candidate = OUT_DIR / run_id
    if candidate.is_dir():
        return candidate
    return None


def _load_summary_and_findings(run_dir: Path) -> tuple[dict, list[dict]]:
    rep = run_dir / "report"
    summary = {}
    findings = []

    # summary
    for name in [
        "summary_unified.json",
        "summary_full_ext.json",
        "summary.json",
    ]:
        p = rep / name
        if p.is_file():
            with p.open("r", encoding="utf-8") as f:
                summary = json.load(f)
            break

    # findings
    for name in [
        "findings_unified.json",
        "findings.json",
        "findings_unified_v2.json",
    ]:
        p = rep / name
        if p.is_file():
            with p.open("r", encoding="utf-8") as f:
                data = json.load(f)
            # findings có thể là list hoặc dict có key "items"
            if isinstance(data, list):
                findings = data
            elif isinstance(data, dict) and "items" in data:
                findings = data.get("items") or []
            break

    return summary, findings


def _render_html_report(run_id: str, summary: dict, findings: list[dict]) -> bytes:
    """Render HTML 'bản thương mại' nhẹ, đủ cho CIO xem nhanh."""
    total = summary.get("total_findings") or summary.get("total") or len(findings)
    by_sev = summary.get("by_severity") or {}
    score = summary.get("security_score", 0)
    top_tool = summary.get("top_risky_tool", "")
    top_cwe = summary.get("top_cwe", "")
    top_module = summary.get("top_module", "")

    now = dt.datetime.now().strftime("%Y-%m-%d %H:%M")

    def sev_val(key):
        return by_sev.get(key, 0)

    # bảng findings chỉ lấy ~200 dòng đầu cho export HTML
    max_rows = 200
    rows = findings[:max_rows]

    html_parts = []
    html_parts.append("<!doctype html>")
    html_parts.append("<html lang='en'>")
    html_parts.append("<head>")
    html_parts.append("<meta charset='utf-8' />")
    html_parts.append("<title>VSP Run Report - {}</title>".format(run_id))
    # inline CSS đơn giản, theo tone VSP 2025
    html_parts.append("""
<style>
body {
  margin: 0;
  padding: 24px;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #050816;
  color: #e5e7eb;
}
h1, h2, h3 {
  margin: 0 0 12px 0;
}
.vsp-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 24px;
}
.vsp-badge {
  display: inline-flex;
  align-items: center;
  padding: 4px 10px;
  border-radius: 999px;
  font-size: 12px;
  background: linear-gradient(to right, #22c55e, #0ea5e9);
  color: #020617;
  font-weight: 600;
}
.vsp-meta {
  font-size: 13px;
  color: #9ca3af;
}
.vsp-kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 24px;
}
.vsp-kpi {
  padding: 12px 14px;
  border-radius: 12px;
  background: radial-gradient(circle at top left, #1e293b, #020617);
  border: 1px solid rgba(148, 163, 184, 0.3);
}
.vsp-kpi-label {
  font-size: 12px;
  color: #9ca3af;
  margin-bottom: 8px;
}
.vsp-kpi-value {
  font-size: 20px;
  font-weight: 600;
}
.vsp-sev-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin-bottom: 24px;
}
.vsp-sev-pill {
  padding: 10px 12px;
  border-radius: 999px;
  font-size: 12px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: rgba(15, 23, 42, 0.9);
  border: 1px solid rgba(55, 65, 81, 0.8);
}
.vsp-sev-pill span:first-child { opacity: 0.8; }
.vsp-sev-critical { color: #f97316; }
.vsp-sev-high { color: #facc15; }
.vsp-sev-medium { color: #22c55e; }
.vsp-sev-low { color: #38bdf8; }
.vsp-sev-info { color: #a855f7; }
.vsp-sev-trace { color: #6b7280; }

.vsp-section-title {
  margin: 0 0 10px 0;
  font-size: 15px;
}
.vsp-table-wrapper {
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid rgba(55, 65, 81, 0.9);
}
table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
thead {
  background: rgba(15, 23, 42, 0.95);
}
th, td {
  padding: 8px 10px;
  border-bottom: 1px solid rgba(31, 41, 55, 0.9);
  text-align: left;
}
th {
  font-weight: 600;
  color: #9ca3af;
  white-space: nowrap;
}
tbody tr:nth-child(even) {
  background: rgba(15, 23, 42, 0.6);
}
.sev-tag {
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 11px;
  font-weight: 600;
}
.sev-critical { background: rgba(248, 113, 113, 0.14); color: #f97316; }
.sev-high     { background: rgba(250, 204, 21, 0.12); color: #facc15; }
.sev-medium   { background: rgba(34, 197, 94, 0.10); color: #22c55e; }
.sev-low      { background: rgba(56, 189, 248, 0.10); color: #38bdf8; }
.sev-info     { background: rgba(168, 85, 247, 0.12); color: #a855f7; }
.sev-trace    { background: rgba(107, 114, 128, 0.15); color: #9ca3af; }

.small {
  font-size: 12px;
  color: #9ca3af;
  margin-top: 6px;
}
</style>
""")
    html_parts.append("</head>")
    html_parts.append("<body>")

    # Header
    html_parts.append("<div class='vsp-header'>")
    html_parts.append("<div>")
    html_parts.append("<div class='vsp-badge'>VersaSecure Platform – EXT+ Profile</div>")
    html_parts.append(f"<h1>Security Run Report – {run_id}</h1>")
    html_parts.append(f"<div class='vsp-meta'>Generated at {now}</div>")
    html_parts.append("</div>")
    html_parts.append(f"<div class='vsp-meta'>Security Score: <strong>{score}</strong></div>")
    html_parts.append("</div>")

    # KPI
    html_parts.append("<div class='vsp-kpi-grid'>")
    html_parts.append(f"<div class='vsp-kpi'><div class='vsp-kpi-label'>Total Findings</div><div class='vsp-kpi-value'>{total}</div></div>")
    html_parts.append(f"<div class='vsp-kpi'><div class='vsp-kpi-label'>Top Risky Tool</div><div class='vsp-kpi-value'>{top_tool or '-'}&nbsp;</div></div>")
    html_parts.append(f"<div class='vsp-kpi'><div class='vsp-kpi-label'>Top CWE</div><div class='vsp-kpi-value'>{top_cwe or '-'}&nbsp;</div></div>")
    html_parts.append(f"<div class='vsp-kpi'><div class='vsp-kpi-label'>Top Module</div><div class='vsp-kpi-value'>{top_module or '-'}&nbsp;</div></div>")
    html_parts.append("</div>")

    # Severity
    html_parts.append("<div class='vsp-sev-grid'>")
    for label, css in [
        ("CRITICAL", "vsp-sev-critical"),
        ("HIGH", "vsp-sev-high"),
        ("MEDIUM", "vsp-sev-medium"),
        ("LOW", "vsp-sev-low"),
        ("INFO", "vsp-sev-info"),
        ("TRACE", "vsp-sev-trace"),
    ]:
        val = sev_val(label)
        html_parts.append(
            f"<div class='vsp-sev-pill {css}'><span>{label}</span><span>{val}</span></div>"
        )
    html_parts.append("</div>")

    # Findings table
    html_parts.append("<h2 class='vsp-section-title'>Top Findings (max 200)</h2>")
    html_parts.append("<div class='vsp-table-wrapper'>")
    html_parts.append("<table>")
    html_parts.append(
        "<thead><tr>"
        "<th>#</th><th>Severity</th><th>Tool</th><th>Rule</th><th>File</th><th>Line</th><th>Message</th>"
        "</tr></thead><tbody>"
    )

    def sev_class(s: str) -> str:
        s_norm = (s or "").upper()
        if s_norm == "CRITICAL":
            return "sev-critical"
        if s_norm == "HIGH":
            return "sev-high"
        if s_norm == "MEDIUM":
            return "sev-medium"
        if s_norm == "LOW":
            return "sev-low"
        if s_norm == "INFO":
            return "sev-info"
        return "sev-trace"

    for idx, it in enumerate(rows, start=1):
        sev = it.get("severity") or it.get("severity_effective") or it.get("raw_severity") or ""
        tool = it.get("tool") or it.get("source") or ""
        rule_id = it.get("rule_id") or it.get("check_id") or ""
        file = it.get("file") or it.get("path") or ""
        line = it.get("line") or it.get("start_line") or ""
        msg = it.get("message") or it.get("shortMessage") or it.get("description") or ""
        sev_cls = sev_class(str(sev))

        html_parts.append("<tr>")
        html_parts.append(f"<td>{idx}</td>")
        html_parts.append(f"<td><span class='sev-tag {sev_cls}'>{sev}</span></td>")
        html_parts.append(f"<td>{tool}</td>")
        html_parts.append(f"<td>{rule_id}</td>")
        html_parts.append(f"<td>{file}</td>")
        html_parts.append(f"<td>{line}</td>")
        html_parts.append(f"<td>{msg}</td>")
        html_parts.append("</tr>")

    html_parts.append("</tbody></table></div>")
    html_parts.append(f"<div class='small'>Total findings in run: {total}. Showing up to {max_rows} rows here.</div>")

    html_parts.append("</body></html>")
    return "\n".join(html_parts).encode("utf-8")


def _render_csv(findings: list[dict]) -> bytes:
    """Xuất CSV đầy đủ findings_unified."""
    output = io.StringIO()
    fieldnames = [
        "severity", "severity_effective", "raw_severity",
        "tool", "source",
        "rule_id", "rule_name",
        "file", "path", "line", "start_line",
        "message", "description",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    for it in findings:
        writer.writerow(it)
    return output.getvalue().encode("utf-8")


@vsp_exports_bp.route("/api/vsp/run_exports_v3", methods=["GET"])
def api_vsp_run_exports_v3():
    run_id = request.args.get("run_id")
    fmt = (request.args.get("format") or "html").lower()

    if not run_id:
        abort(400, "Missing run_id")

    run_dir = _find_run_dir(run_id)
    if not run_dir:
        abort(404, f"Run not found: {run_id}")

    summary, findings = _load_summary_and_findings(run_dir)

    if fmt == "html":
        data = _render_html_report(run_id, summary, findings)
        resp = make_response(data)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        resp.headers["Content-Disposition"] = f'inline; filename="{run_id}.html"'
        return resp

    if fmt == "csv":
        data = _render_csv(findings)
        resp = make_response(data)
        resp.headers["Content-Type"] = "text/csv; charset=utf-8"
        resp.headers["Content-Disposition"] = f'attachment; filename="{run_id}.csv"'
        return resp

    abort(400, f"Unsupported format: {fmt}")


@vsp_exports_bp.route("/api/vsp/run_full_ext", methods=["POST"])
def api_vsp_run_full_ext():
    \"\"\"Trigger VSP FULL EXT scan từ UI Settings.

    Mapping đúng CLI:
        bin/run_vsp_full_ext.sh SRC

    SRC lấy từ Default source path trên tab Settings.
    \"\"\"
    from flask import request, jsonify, current_app
    from pathlib import Path
    import subprocess
    import os

    try:
        data = request.get_json(force=True) or {}
        src = (data.get("src") or "").strip()
        profile = (data.get("profile") or "EXT").strip().upper() or "EXT"

        if not src:
            return jsonify({"ok": False, "error": "missing_src"}), 400

        # ROOT = /home/test/Data/SECURITY_BUNDLE
        root = Path(__file__).resolve().parent.parent
        script = root / "bin" / "run_vsp_full_ext.sh"

        if not script.is_file():
            return jsonify(
                {
                    "ok": False,
                    "error": "script_not_found",
                    "script": str(script),
                }
            ), 500

        env = os.environ.copy()
        # Cho phép script dùng PROFILE/LEVEL nếu cần
        env.setdefault("PROFILE", profile)
        env.setdefault("LEVEL", profile)

        cmd = [str(script), src]
        current_app.logger.info("[VSP][RUN] starting FULL EXT: %s", " ".join(cmd))

        # Chạy nền, không block Flask
        proc = subprocess.Popen(
            cmd,
            cwd=str(root),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=env,
        )

        return jsonify(
            {
                "ok": True,
                "started": True,
                "pid": proc.pid,
                "src": src,
                "profile": profile,
                "cmd": " ".join(cmd),
            }
        )
    except Exception as e:
        current_app.logger.exception("[VSP][RUN] failed: %r", e)
        return jsonify({"ok": False, "error": "exception"}), 500
