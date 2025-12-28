#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap

app_path = Path("app.py")
data = app_path.read_text(encoding="utf-8")

marker = '@app.route("/")'
idx = data.find(marker)
if idx == -1:
    raise SystemExit("Không tìm thấy @app.route(\"/\") trong app.py")

before = data[:idx]

rest = data[idx:]
# tìm route tiếp theo để cắt block index cũ
next_route_idx = rest.find("@app.route(", len(marker))
if next_route_idx == -1:
    rest_after = ""
else:
    rest_after = rest[next_route_idx:]

body_new = textwrap.dedent("""
@app.route("/")
def index():
    \"\"\"Dashboard chính: luôn đọc RUN_* mới nhất + summary_unified.json.\"\"\"
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = root / "out"

    run_dirs = sorted(
        [
            p for p in out_dir.glob("RUN_*")
            if p.is_dir() and not p.name.startswith("RUN_DEMO_")
        ],
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )

    summary = {
        "run_id": None,
        "src": "",
        "total": 0,
        "critical": 0,
        "high": 0,
        "medium": 0,
        "low": 0,
        "info": 0,
        "tools": [],
    }

    if run_dirs:
        run_dir = run_dirs[0]
        report_dir = run_dir / "report"
        summary_path = report_dir / "summary_unified.json"

        if summary_path.is_file():
            try:
                raw = json.loads(summary_path.read_text(encoding="utf-8"))
            except Exception as e:
                print(f"[ERR][INDEX] Lỗi đọc summary_unified.json: {e}")
                raw = {}
        else:
            print(f"[WARN][INDEX] Không tìm thấy {summary_path}")
            raw = {}

        total = (
            raw.get("total_findings")
            or raw.get("total")
            or raw.get("total_findings_all")
            or 0
        )

        sev_raw = raw.get("by_severity") or raw.get("severity") or {}
        sev_norm = {str(k).upper(): int(v) for k, v in sev_raw.items()}

        summary.update(
            {
                "run_id": run_dir.name,
                "src": raw.get("src") or raw.get("SRC") or "",
                "total": int(total),
                "critical": sev_norm.get("CRITICAL", 0),
                "high": sev_norm.get("HIGH", 0),
                "medium": sev_norm.get("MEDIUM", 0),
                "low": sev_norm.get("LOW", 0),
                "info": sev_norm.get("INFO", 0),
            }
        )

        tools_raw = raw.get("by_tool") or raw.get("tools") or {}
        tools = []
        for name, counts in tools_raw.items():
            if isinstance(counts, dict):
                c = {str(k).upper(): int(v) for k, v in counts.items()}
            else:
                c = {}
            tools.append(
                {
                    "name": name,
                    "critical": c.get("CRITICAL", 0),
                    "high": c.get("HIGH", 0),
                    "medium": c.get("MEDIUM", 0),
                    "low": c.get("LOW", 0),
                    "info": c.get("INFO", 0),
                }
            )

        summary["tools"] = tools

    print(
        f"[INFO][INDEX] RUN={summary['run_id']}, total={summary['total']}, "
        f"C={summary['critical']}, H={summary['high']}, "
        f"M={summary['medium']}, L={summary['low']}"
    )

    return render_template("index.html", summary=summary)
""").lstrip()

new_data = before + body_new + "\n\n" + rest_after
app_path.write_text(new_data, encoding="utf-8")
print("[OK] Đã patch route / (index) trong app.py")
PY
