#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
API_DIR="$ROOT/api"
TPL_DIR="$ROOT/templates"

echo "[PATCH] VSP – run_export_v3 (HTML / PDF / ZIP)"

############################################
# 1) Tạo API blueprint: api/vsp_run_export_api_v3.py
############################################
cat > "$API_DIR/vsp_run_export_api_v3.py" << 'PY'
from flask import Blueprint, request, jsonify, send_file, render_template, make_response
from pathlib import Path
import json
import io
import zipfile
import subprocess
import shutil

bp_run_export_v3 = Blueprint("bp_run_export_v3", __name__)

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "out"

def load_summary(run_dir: Path, run_id: str):
    report_dir = run_dir / "report"
    summary_path = report_dir / "summary_unified.json"
    if summary_path.is_file():
        try:
            return json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            pass
    # fallback tối thiểu
    return {
        "run_id": run_id,
        "total_findings": 0,
        "security_score": None,
        "by_severity": {},
        "by_tool": {},
        "top_cwe": None,
        "top_module": None,
    }

@bp_run_export_v3.route("/api/vsp/run_export_v3", methods=["GET"])
def run_export_v3():
    run_id = request.args.get("run_id", "").strip()
    fmt = (request.args.get("fmt") or "html").lower()

    if not run_id:
        return jsonify(ok=False, error="Missing run_id"), 400

    run_dir = OUT_DIR / run_id
    if not run_dir.is_dir():
        return jsonify(ok=False, error=f"Run dir not found: {run_dir}"), 404

    summary = load_summary(run_dir, run_id)

    # HTML luôn generate trước, dùng lại cho HTML/PDF
    html = render_template("vsp_run_report_cio_v3.html",
                           run_id=run_id,
                           summary=summary)

    # 1) HTML
    if fmt == "html":
        resp = make_response(html)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        filename = f"{run_id}_vsp_report.html"
        # mặc định cho download
        if request.args.get("inline") == "1":
            # xem trên browser
            pass
        else:
            resp.headers["Content-Disposition"] = f'attachment; filename="{filename}"'
        return resp

    # 2) PDF – dùng wkhtmltopdf nếu có
    if fmt == "pdf":
        if not shutil.which("wkhtmltopdf"):
            return jsonify(ok=False,
                           error="wkhtmltopdf not installed on server – cannot build PDF"), 500
        try:
            proc = subprocess.run(
                ["wkhtmltopdf", "-q", "-", "-"],
                input=html.encode("utf-8"),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if proc.returncode != 0:
                return jsonify(
                    ok=False,
                    error="wkhtmltopdf failed",
                    stderr=proc.stderr.decode("utf-8", errors="ignore"),
                ), 500

            pdf_bytes = proc.stdout
            buf = io.BytesIO(pdf_bytes)
            buf.seek(0)
            return send_file(
                buf,
                mimetype="application/pdf",
                as_attachment=True,
                download_name=f"{run_id}_vsp_report.pdf",
            )
        except Exception as ex:
            return jsonify(ok=False, error=f"PDF export error: {ex}"), 500

    # 3) ZIP – bundle full run dir (evidence)
    if fmt == "zip":
        mem = io.BytesIO()
        with zipfile.ZipFile(mem, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for p in run_dir.rglob("*"):
                if p.is_file():
                    arc = p.relative_to(run_dir)
                    zf.write(p, arcname=arc)
        mem.seek(0)
        return send_file(
            mem,
            mimetype="application/zip",
            as_attachment=True,
            download_name=f"{run_id}_vsp_full_bundle.zip",
        )

    return jsonify(ok=False, error=f"Unsupported fmt: {fmt}"), 400
PY

echo "[PATCH] Đã ghi $API_DIR/vsp_run_export_api_v3.py"

############################################
# 2) Template HTML CIO-level single-run report
############################################
cat > "$TPL_DIR/vsp_run_report_cio_v3.html" << 'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>VSP Run Report – {{ run_id }}</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <link rel="stylesheet" href="/static/css/vsp_ui_layout.css" />
  <style>
    body {
      background: #020617;
      color: #e5e7eb;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Inter", sans-serif;
      padding: 24px;
    }
    .report-container {
      max-width: 1200px;
      margin: 0 auto;
      background: radial-gradient(circle at top left, #0f172a, #020617);
      border-radius: 24px;
      padding: 32px 32px 40px;
      box-shadow: 0 24px 80px rgba(0,0,0,0.75);
    }
    .report-header {
      display: flex;
      justify-content: space-between;
      gap: 24px;
      align-items: flex-start;
      margin-bottom: 24px;
      border-bottom: 1px solid rgba(148,163,184,0.3);
      padding-bottom: 16px;
    }
    .report-title {
      font-size: 24px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      color: #f9fafb;
    }
    .report-subtitle {
      font-size: 14px;
      color: #9ca3af;
      margin-top: 4px;
    }
    .report-meta {
      text-align: right;
      font-size: 13px;
      color: #9ca3af;
    }
    .badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      border-radius: 999px;
      padding: 4px 12px;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      border: 1px solid rgba(148,163,184,0.5);
      color: #e5e7eb;
    }
    .badge-pill {
      background: linear-gradient(135deg,#22c55e,#15803d);
      border-color: transparent;
      color: #022c22;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;
      margin-top: 24px;
    }
    .card {
      background: radial-gradient(circle at top, #0b1120, #020617);
      border-radius: 18px;
      padding: 14px 16px 16px;
      border: 1px solid rgba(30,64,175,0.4);
    }
    .card-title {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      color: #9ca3af;
      margin-bottom: 6px;
    }
    .card-value {
      font-size: 22px;
      font-weight: 600;
      color: #f9fafb;
    }
    .card-sub {
      font-size: 11px;
      color: #9ca3af;
      margin-top: 2px;
    }
    .card-severity-crit   { border-color: #ef4444; }
    .card-severity-high   { border-color: #f97316; }
    .card-severity-med    { border-color: #eab308; }
    .card-severity-low    { border-color: #22c55e; }
    .card-severity-info   { border-color: #38bdf8; }
    .card-severity-trace  { border-color: #64748b; }

    .section-title {
      margin-top: 28px;
      margin-bottom: 10px;
      font-size: 13px;
      text-transform: uppercase;
      letter-spacing: 0.16em;
      color: #9ca3af;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 12px;
    }
    th, td {
      padding: 8px 10px;
      border-bottom: 1px solid rgba(30,64,175,0.35);
    }
    th {
      text-align: left;
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.1em;
      color: #9ca3af;
    }
    tbody tr:nth-child(odd) {
      background: rgba(15,23,42,0.7);
    }
    code {
      font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace;
      font-size: 12px;
      color: #e5e7eb;
    }
    .muted {
      color: #6b7280;
      font-size: 11px;
    }
  </style>
</head>
<body>
  <div class="report-container">
    <div class="report-header">
      <div>
        <div class="report-title">VersaSecure Platform (VSP) – Run report</div>
        <div class="report-subtitle">
          Multi-tool security analytics • CIO-level snapshot for a single run.
        </div>
      </div>
      <div class="report-meta">
        <div><span class="badge badge-pill">RUN</span></div>
        <div style="margin-top:6px;"><code>{{ run_id }}</code></div>
        <div style="margin-top:4px;">
          <span class="muted">
            Generated at:
            {{ summary.generated_at or "-" }}
          </span>
        </div>
      </div>
    </div>

    {# KPI row #}
    {% set sev = summary.by_severity or {} %}
    <div class="grid">
      <div class="card">
        <div class="card-title">Total findings</div>
        <div class="card-value">
          {{ summary.total_findings or 0 }}
        </div>
        <div class="card-sub">All tools • 6 severity buckets</div>
      </div>

      <div class="card card-severity-crit">
        <div class="card-title">Critical</div>
        <div class="card-value">{{ sev.CRITICAL or sev.get('CRITICAL', 0) or 0 }}</div>
        <div class="card-sub">Blocker issues</div>
      </div>

      <div class="card card-severity-high">
        <div class="card-title">High</div>
        <div class="card-value">{{ sev.HIGH or sev.get('HIGH', 0) or 0 }}</div>
        <div class="card-sub">High risk findings</div>
      </div>

      <div class="card card-severity-med">
        <div class="card-title">Medium</div>
        <div class="card-value">{{ sev.MEDIUM or sev.get('MEDIUM', 0) or 0 }}</div>
        <div class="card-sub">Medium risk findings</div>
      </div>
    </div>

    <div class="grid" style="margin-top:14px;">
      <div class="card card-severity-low">
        <div class="card-title">Low</div>
        <div class="card-value">{{ sev.LOW or sev.get('LOW', 0) or 0 }}</div>
        <div class="card-sub">Low severity</div>
      </div>

      <div class="card card-severity-info">
        <div class="card-title">Info</div>
        <div class="card-value">{{ sev.INFO or sev.get('INFO', 0) or 0 }}</div>
        <div class="card-sub">Informational / best practice</div>
      </div>

      <div class="card card-severity-trace">
        <div class="card-title">Trace</div>
        <div class="card-value">{{ sev.TRACE or sev.get('TRACE', 0) or 0 }}</div>
        <div class="card-sub">Noise / telemetry</div>
      </div>

      <div class="card">
        <div class="card-title">Security posture score</div>
        <div class="card-value">
          {{ summary.security_score if summary.security_score is not none else "-/100" }}
        </div>
        <div class="card-sub">Weighted by CRIT/HIGH &amp; CWE</div>
      </div>
    </div>

    {# By tool #}
    <div class="section-title">Tool coverage – findings per tool</div>
    {% set bt = summary.by_tool or {} %}
    {% if bt %}
      <table>
        <thead>
          <tr>
            <th>Tool</th>
            <th>Total findings</th>
          </tr>
        </thead>
        <tbody>
          {% for tool, count in bt.items() %}
          <tr>
            <td>{{ tool }}</td>
            <td>{{ count }}</td>
          </tr>
          {% endfor %}
        </tbody>
      </table>
    {% else %}
      <div class="muted">No tool breakdown information available.</div>
    {% endif %}

    <div class="section-title">Key exposure</div>
    <table>
      <tbody>
        <tr>
          <th style="width: 25%;">Top impacted CWE</th>
          <td>{{ summary.top_cwe or "-" }}</td>
        </tr>
        <tr>
          <th>Most vulnerable module</th>
          <td>{{ summary.top_module or "-" }}</td>
        </tr>
      </tbody>
    </table>

    <div class="section-title">Notes</div>
    <p class="muted">
      This report is generated by VersaSecure Platform (VSP) from the unified
      security findings (multi-tool). It is intended to be attached to
      change requests, risk registers, and audit evidence (ISO 27001 /
      DevSecOps governance).
    </p>
  </div>
</body>
</html>
HTML

echo "[PATCH] Đã ghi $TPL_DIR/vsp_run_report_cio_v3.html"

############################################
# 3) Gắn blueprint vào vsp_demo_app.py
############################################
PYTHON=$(command -v python3 || command -v python)

$PYTHON << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

if "bp_run_export_v3" in txt:
    print("[PATCH] bp_run_export_v3 đã tồn tại trong vsp_demo_app.py")
else:
    # 3.1 import
    if "from api.vsp_run_export_api_v3 import bp_run_export_v3" not in txt:
        if "from api.api_vsp_dashboard_v3 import bp_dashboard_v3" in txt:
            txt = txt.replace(
                "from api.api_vsp_dashboard_v3 import bp_dashboard_v3",
                "from api.api_vsp_dashboard_v3 import bp_dashboard_v3\nfrom api.vsp_run_export_api_v3 import bp_run_export_v3",
            )
        else:
            txt = "from api.vsp_run_export_api_v3 import bp_run_export_v3\n" + txt

    # 3.2 register blueprint
    if "app.register_blueprint(bp_run_export_v3)" not in txt:
        if "app.register_blueprint(bp_dashboard_v3)" in txt:
            txt = txt.replace(
                "app.register_blueprint(bp_dashboard_v3)",
                "app.register_blueprint(bp_dashboard_v3)\napp.register_blueprint(bp_run_export_v3)",
            )
        else:
            txt = txt.replace(
                "app = Flask(__name__)",
                "app = Flask(__name__)\napp.register_blueprint(bp_run_export_v3)",
            )

    backup = p.with_suffix(p.suffix + ".bak_run_export_v3")
    backup.write_text(p.read_text(encoding="utf-8"), encoding="utf-8")
    p.write_text(txt, encoding="utf-8")
    print("[PATCH] Đã patch vsp_demo_app.py (backup ->", backup.name, ")")
PY

echo "[PATCH] Done."
