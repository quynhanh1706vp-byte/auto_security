#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap, re

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

# Tìm block route /api/runs
idx = code.find('@app.route("/api/runs"')
if idx == -1:
    idx = code.find("@app.route('/api/runs'")
if idx == -1:
    print("[ERR] Không tìm thấy @app.route('/api/runs') trong app.py")
    sys.exit(1)

def_idx = code.find("def ", idx)
if def_idx == -1:
    print("[ERR] Không tìm thấy def sau route /api/runs")
    sys.exit(1)

end = code.find("\n@app.route", def_idx + 1)
if end == -1:
    end = len(code)

before = code[:idx]
after = code[end:]

new_block = textwrap.dedent("""
@app.route("/api/runs", methods=["GET"])
def api_runs():
    # API trả danh sách RUN_* cho tab Run & Report.
    from pathlib import Path
    from flask import jsonify
    import json, datetime, re

    root = Path("/home/test/Data/SECURITY_BUNDLE")
    out_dir = root / "out"
    runs = []

    if not out_dir.is_dir():
        return jsonify({"runs": []})

    # Lấy các thư mục RUN_* đúng pattern (bỏ RUN_DEMO...)
    entries = []
    for p in out_dir.iterdir():
        if not p.is_dir():
            continue
        name = p.name
        if not re.match(r"^RUN_\\d{8}_\\d{6}$", name):
            continue
        if name.startswith("RUN_DEMO"):
            continue
        entries.append(p)

    # Sort mới nhất trước
    entries.sort(key=lambda p: p.name, reverse=True)

    for run_dir in entries:
        name = run_dir.name
        report_dir = run_dir / "report"
        summary_path = report_dir / "summary_unified.json"

        total = 0
        crit = 0
        high = 0
        has_counts = False

        if summary_path.is_file():
            try:
                with summary_path.open("r", encoding="utf-8") as f:
                    summary = json.load(f)

                # Kiểu 1: dict có severity_buckets
                if isinstance(summary, dict):
                    buckets = (
                        summary.get("severity_buckets")
                        or summary.get("severityBuckets")
                        or summary.get("buckets")
                        or {}
                    )
                    if isinstance(buckets, dict):
                        crit = int(buckets.get("critical", 0) or 0)
                        high = int(buckets.get("high", 0) or 0)
                        med = int(buckets.get("medium", 0) or 0)
                        low = int(buckets.get("low", 0) or 0)
                        total = int(
                            summary.get("total_findings", crit + high + med + low) or 0
                        )
                        has_counts = True

                # Kiểu 2: list [{severity, count}, ...]
                if not has_counts and isinstance(summary, list):
                    total_tmp = 0
                    crit_tmp = 0
                    high_tmp = 0
                    for item in summary:
                        if not isinstance(item, dict):
                            continue
                        sev = str(item.get("severity", "")).lower()
                        cnt = int(item.get("count", 0) or 0)
                        total_tmp += cnt
                        if sev == "critical":
                            crit_tmp += cnt
                        elif sev == "high":
                            high_tmp += cnt
                    if total_tmp > 0 or crit_tmp > 0 or high_tmp > 0:
                        total = total_tmp
                        crit = crit_tmp
                        high = high_tmp
                        has_counts = True

            except Exception as e:  # noqa: BLE001
                print(f"[WARN][API] Runs: error reading {summary_path}: {e!r}")

        # Nếu không đọc được gì, vẫn trả về với số liệu 0
        if not has_counts:
            total = int(total or 0)
            crit = int(crit or 0)
            high = int(high or 0)

        crit_high = crit + high

        # Lấy thời gian từ mtime của thư mục RUN
        try:
            mtime = datetime.datetime.fromtimestamp(run_dir.stat().st_mtime)
            time_str = mtime.strftime("%Y-%m-%d %H:%M:%S")
        except Exception:  # noqa: BLE001
            time_str = ""

        runs.append(
            {
                "run_id": name,
                "time": time_str,
                "total": total,
                "critical": crit,
                "high": high,
                "crit_high": crit_high,
            }
        )

    return jsonify({"runs": runs})
""").lstrip("\n")

code_new = before + new_block + "\n" + after
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã ghi lại block /api/runs sạch, không docstring lỗi.")
PY
