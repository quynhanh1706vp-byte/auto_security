#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
cp "$APP" "$APP.bak_patch_runs_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$APP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

old = '''@app.route("/runs")
def runs():
    """Runs & Reports history from out/RUN_* (newest first)."""
    base = Path(__file__).resolve().parents[1]
    out_dir = base / "out"
    runs = []
    if out_dir.is_dir():
        for run_dir in sorted(out_dir.glob("RUN_*"), reverse=True):
            report_dir = run_dir / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                raw = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            sev = raw.get("severity_counts") or raw.get("SEVERITY_COUNTS") or {}
            total = raw.get("total_findings") or raw.get("TOTAL_FINDINGS") or 0
            runs.append({
                "run_id": run_dir.name,
                "run_path": str(run_dir),
                "total": int(total),
                "critical": int(sev.get("CRITICAL", 0)),
                "high": int(sev.get("HIGH", 0)),
                "medium": int(sev.get("MEDIUM", 0)),
                "low": int(sev.get("LOW", 0)),
            })
            if len(runs) >= 100:
                break
    latest_run_id = runs[0]["run_id"] if runs else None
    return render_template("runs.html", runs=runs, latest_run_id=latest_run_id,)'''

new = '''@app.route("/runs")
def runs():
    """Runs & Reports history from out/RUN_* (newest first)."""
    base = Path(__file__).resolve().parents[1]
    out_dir = base / "out"
    runs = []
    if out_dir.is_dir():
        for run_dir in sorted(out_dir.glob("RUN_*"), reverse=True):
            report_dir = run_dir / "report"
            summary_path = report_dir / "summary_unified.json"
            if not summary_path.is_file():
                continue
            try:
                raw = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception:
                continue
            sev = raw.get("severity_counts") or raw.get("SEVERITY_COUNTS") or {}
            total = raw.get("total_findings") or raw.get("TOTAL_FINDINGS") or 0
            runs.append({
                "run_id": run_dir.name,
                "run_path": str(run_dir),
                "total": int(total),
                "critical": int(sev.get("CRITICAL", 0)),
                "high": int(sev.get("HIGH", 0)),
                "medium": int(sev.get("MEDIUM", 0)),
                "low": int(sev.get("LOW", 0)),
            })
            if len(runs) >= 100:
                break
    print(f"[INFO][RUNS] Tổng RUN phát hiện: {len(runs)}")
    latest_run_id = runs[0]["run_id"] if runs else None
    return render_template("runs.html", runs=runs, run_rows=runs, latest_run_id=latest_run_id)'''

if old not in data:
    print("[WARN] Không tìm thấy block /runs cũ để replace.")
else:
    data = data.replace(old, new)
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã patch route /runs (thêm run_rows + log).")
PY
