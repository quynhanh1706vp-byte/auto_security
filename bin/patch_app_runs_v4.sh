#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

APP="app.py"
echo "[i] Patching $APP để thêm backend lịch sử RUN..."

python3 - <<'PY'
from pathlib import Path
import json

root = Path(__file__).resolve().parent
app_path = root / "app.py"

text = app_path.read_text(encoding="utf-8")

marker = "if __name__ == '__main__':"
if "BEGIN_RUNS_V2" in text:
    print("[INFO] Đã có BEGIN_RUNS_V2 trong app.py, bỏ qua.")
else:
    if marker not in text:
        raise SystemExit("[ERROR] Không tìm thấy đoạn 'if __name__ == \"__main__\"' trong app.py")

    before, after = text.split(marker, 1)

    snippet = '''

# === BEGIN_RUNS_V2 ===
from pathlib import Path as _SBPath
import json as _SBjson

def _sb_out_dir():
    # app.py nằm trong SECURITY_BUNDLE/ui → out ở SECURITY_BUNDLE/out
    ui_root = _SBPath(__file__).resolve().parent
    return ui_root.parent / "out"

def _sb_collect_runs():
    out_dir = _sb_out_dir()
    runs = []
    if not out_dir.is_dir():
        return runs

    # RUN_* mới nhất đứng đầu
    for d in sorted(out_dir.glob("RUN_*"), reverse=True):
        summary = d / "report" / "summary_unified.json"
        if not summary.is_file():
            continue
        try:
            data = _SBjson.loads(summary.read_text(encoding="utf-8"))
        except Exception:
            continue

        sev = data.get("severity_counts") or data.get("SEVERITY_COUNTS") or {}
        runs.append({
            "run_id": d.name,
            "total": int(data.get("total_findings") or data.get("TOTAL_FINDINGS") or 0),
            "C": int(sev.get("CRITICAL", 0) or 0),
            "H": int(sev.get("HIGH", 0) or 0),
            "M": int(sev.get("MEDIUM", 0) or 0),
            "L": int(sev.get("LOW", 0) or 0),
        })

    return runs

@app.route('/runs')
def runs_page():
    runs = _sb_collect_runs()
    return render_template('runs.html', runs=runs)
# === END_RUNS_V2 ===

'''
    app_path.write_text(before + snippet + marker + after, encoding="utf-8")
    print("[OK] Đã chèn backend /runs (BEGIN_RUNS_V2) vào app.py")
PY

echo "[DONE] patch_app_runs_v4.sh hoàn thành."
