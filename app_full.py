import os, glob, json
from flask import Flask, render_template, send_file, request, redirect, url_for
import pdfkit

app = Flask(__name__, static_folder="static", template_folder="templates")

OUT_DIR = os.path.join(os.path.dirname(__file__), "out")

def find_latest_run():
    runs = sorted(glob.glob(os.path.join(OUT_DIR, "*_RUN_*")), reverse=True)
    return runs[0] if runs else None

def load_json(path):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None

@app.route("/")
def dashboard():
    run_path = find_latest_run()
    if not run_path:
        return "<h2>No runs found</h2>"
    # Example: load semgrep findings
    sem = load_json(os.path.join(run_path, "semgrep", "semgrep.json")) or {}
    band = load_json(os.path.join(run_path, "bandit", "bandit.json")) or {}
    gr = load_json(os.path.join(run_path, "grype", "grype.json")) or {}
    gl = load_json(os.path.join(run_path, "gitleaks", "gitleaks.json")) or {}
    # Simple summary counts — giả sử JSON structure có keys 'findings'
    total = sum(len(d.get("findings", [])) for d in [sem, band, gr, gl])
    high = sum(sum(1 for f in d.get("findings", []) if f.get("severity") in ("HIGH","CRITICAL")) for d in [sem, band, gr, gl])
    medium = sum(sum(1 for f in d.get("findings", []) if f.get("severity")=="MEDIUM") for d in [sem, band, gr, gl])
    low = total - high - medium
    return render_template("dashboard.html",
        total=total, high=high, medium=medium, low=low, run_name=os.path.basename(run_path))

@app.route("/runs")
def runs():
    runs = sorted(glob.glob(os.path.join(OUT_DIR, "*_RUN_*")), reverse=True)
    return render_template("runs.html", runs=[os.path.basename(r) for r in runs])

@app.route("/report/<run_name>")
def report(run_name):
    rp = os.path.join(OUT_DIR, run_name, "report", "report.html")
    if os.path.exists(rp):
        return send_file(rp)
    else:
        return f"No report HTML for {run_name}", 404

@app.route("/export_pdf/<run_name>")
def export_pdf(run_name):
    rp = os.path.join(OUT_DIR, run_name, "report", "report.html")
    pdf_out = os.path.join(OUT_DIR, run_name, "report.pdf")
    pdfkit.from_file(rp, pdf_out, options={"encoding":"UTF-8"})
    return send_file(pdf_out, as_attachment=True)

@app.route("/settings")
def settings():
    return render_template("settings.html")

@app.route("/rules")
def rules():
    return render_template("rules_override.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8905, debug=True)
