#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, os, json
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

marker = 'if __name__ == "__main__":'
if marker not in data:
    print("[ERR] Không tìm thấy 'if __name__ == \"__main__\":' trong app.py")
    raise SystemExit(1)

block = '''
@app.route("/api/runs")
def api_runs():
    """
    Trả về danh sách các RUN_* có report/summary_unified.json
    để fill bảng 'LAST RUNS & REPORTS'.
    """
    ROOT = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = ROOT / "out"

    if not out_dir.is_dir():
        return {"runs": [], "error": f"Not found: {out_dir}"}

    rows = []

    for name in sorted(os.listdir(out_dir)):
        # chỉ lấy RUN ngày tháng, bỏ RUN_DEMO_, RUN_GITLEAKS_EXT_...
        if not (name.startswith("RUN_2") and "_" in name[4:]):
            continue

        run_dir = out_dir / name
        report_dir = run_dir / "report"
        summary_path = report_dir / "summary_unified.json"

        if not summary_path.is_file():
            continue

        try:
            with summary_path.open("r", encoding="utf-8") as f:
                s = json.load(f)
        except Exception:
            continue

        # parse time từ tên RUN_YYYYmmdd_HHMMSS
        # ví dụ RUN_20251122_231149
        run_id = name
        time_str = ""
        try:
            dt = name[4:]
            date_part, time_part = dt.split("_", 1)
            time_str = f"{date_part[0:4]}-{date_part[4:6]}-{date_part[6:8]} {time_part[0:2]}:{time_part[2:4]}:{time_part[4:6]}"
        except Exception:
            # fallback: dùng mtime
            ts = summary_path.stat().st_mtime
            import datetime as _dt
            time_str = _dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")

        total   = s.get("total", 0)
        crit    = s.get("critical", s.get("crit", 0))
        high    = s.get("high", 0)
        medium  = s.get("medium", 0)
        low     = s.get("low", 0)
        info    = s.get("info", 0)
        ch      = (crit or 0) + (high or 0)

        row = {
            "run": run_id,
            "time": time_str,
            "total": total,
            "critical": crit,
            "high": high,
            "medium": medium,
            "low": low,
            "info": info,
            "ch": ch,
            # link report HTML theo route sẵn có /report/<RUN>/html
            "report_url": f"/report/{run_id}/html",
        }
        rows.append(row)

    # sort RUN mới nhất lên đầu
    rows.sort(key=lambda r: r["run"], reverse=True)

    return {"runs": rows}
'''

if "/api/runs" in data:
    print("[OK] app.py đã có /api/runs, bỏ qua.")
    raise SystemExit(0)

new_data = data.replace(marker, block + "\n\n" + marker, 1)
path.write_text(new_data, encoding="utf-8")
print("[OK] Đã chèn route /api/runs TRƯỚC if __main__ trong app.py")
PY
