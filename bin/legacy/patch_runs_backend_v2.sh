#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

python3 - <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")

if "def _sb_scan_runs(" in data:
    print("[INFO] Đã có helper _sb_scan_runs, bỏ qua append.")
    raise SystemExit(0)

marker = "app = Flask(__name__"
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không tìm thấy 'app = Flask(__name__' trong app.py – dừng.")
    raise SystemExit(1)
idx = data.find("\n", idx)

insert_code = textwrap.dedent("""
    # === Helpers cho Runs & Reports ===
    def _sb_scan_runs(max_items: int = 50):
        \"\"\"Scan thư mục out/ để lấy danh sách RUN_* + *_RUN_* mới nhất.

        Trả về list[dict] với các field:
          - run_id
          - total, c, h, m, l
          - report_html (link tới PM-style report nếu có)
        \"\"\"
        import os, json
        from pathlib import Path

        ROOT = Path(__file__).resolve().parent.parent
        out_dir = ROOT / "out"
        if not out_dir.exists():
            return []

        def norm_int(x):
            try:
                return int(x)
            except Exception:
                return 0

        runs = []
        for d in sorted(out_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
            if not d.is_dir():
                continue
            name = d.name
            if "RUN" not in name:
                continue

            report_dir = d / "report"
            summary_path = report_dir / "summary_unified.json"
            total = c = h = m = l = 0
            if summary_path.exists():
                try:
                    js = json.loads(summary_path.read_text(encoding="utf-8"))
                    total = norm_int(js.get("total_findings") or js.get("TOTAL_FINDINGS") or 0)
                    sev = js.get("severity_counts") or js.get("SEVERITY_COUNTS") or {}
                    c = norm_int(sev.get("CRITICAL") or sev.get("Critical") or 0)
                    h = norm_int(sev.get("HIGH") or 0)
                    m = norm_int(sev.get("MEDIUM") or 0)
                    l = norm_int(sev.get("LOW") or 0)
                except Exception:
                    pass

            report_html = None
            pm = report_dir / "security_resilient.html"
            if pm.exists():
                report_html = f"/pm_report/{name}/html"

            runs.append({
                "run_id": name,
                "total": total,
                "c": c,
                "h": h,
                "m": m,
                "l": l,
                "report_html": report_html,
            })
            if len(runs) >= max_items:
                break
        return runs

    @app.route("/runs")
    def runs_page():
        \"\"\"Trang Runs & Reports – bảng history các RUN trong out/.\"\"\"
        runs = _sb_scan_runs()
        return render_template("runs.html", runs=runs)
""")

new_data = data[:idx+1] + insert_code + data[idx+1:]
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn helper _sb_scan_runs + route /runs vào app.py")
PY
