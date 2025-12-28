#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

# backup nhẹ
cp "$APP" "$APP.bak_$(date +%Y%m%d_%H%M%S)" || true

python3 - "$APP" <<'PY'
from pathlib import Path
import textwrap
import re

path = Path("app.py")
data = path.read_text(encoding="utf-8")

# tìm decorator route("/")
pattern = r"@app\.route\(\s*['\"]/['\"][^)]*\)"
m = re.search(pattern, data)

if m:
    start = m.start()
    rest = data[start:]
    m2 = re.search(r"\n@app\.route\(", rest[1:])
    if m2:
        end = start + 1 + m2.start()   # cắt tới trước decorator kế tiếp
    else:
        end = len(data)
    before = data[:start]
    after = data[end:]
else:
    # không có route("/") cũ → cứ append vào cuối file
    before = data.rstrip() + "\n\n"
    after = ""

body_new = textwrap.dedent('''
@app.route("/")
def index():
    """Dashboard main: always read latest RUN_* summary_unified.json."""
    import json
    from pathlib import Path

    root = Path(__file__).resolve().parent.parent  # /home/test/Data/SECURITY_BUNDLE
    out_dir = root / "out"

    run_dirs = sorted(
        [p for p in out_dir.glob("RUN_*") if p.is_dir() and not p.name.startswith("RUN_DEMO_")],
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
        try:
            raw = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"[ERR][INDEX] cannot read {summary_path}: {e}")
            raw = {}

        # tổng findings
        total = (
            raw.get("total_findings")
            or raw.get("TOTAL_FINDINGS")
            or raw.get("total")
            or raw.get("total_findings_all")
            or 0
        )

        # severity – ưu tiên severity_counts
        sev_raw = (
            raw.get("severity_counts")
            or raw.get("SEVERITY_COUNTS")
            or raw.get("by_severity")
            or raw.get("severity")
            or {}
        )
        sev = {str(k).upper(): int(v) for k, v in sev_raw.items()}

        summary.update(
            {
                "run_id": run_dir.name,
                "src": raw.get("src") or raw.get("SRC") or "",
                "total": int(total),
                "critical": sev.get("CRITICAL", 0),
                "high": sev.get("HIGH", 0),
                "medium": sev.get("MEDIUM", 0),
                "low": sev.get("LOW", 0),
                "info": sev.get("INFO", 0),
            }
        )

        # BY_TOOL / by_tool – hiện tại chỉ có tổng "count" cho mỗi tool
        tools_raw = raw.get("by_tool") or raw.get("BY_TOOL") or raw.get("tools") or {}
        tools = []
        for name, counts in tools_raw.items():
            if isinstance(counts, dict):
                count = int(counts.get("count", 0))
            else:
                try:
                    count = int(counts)
                except Exception:
                    count = 0
            tools.append({"name": name, "count": count})
        summary["tools"] = tools

    print(
        f"[INFO][INDEX] RUN={summary['run_id']}, total={summary['total']}, "
        f"C={summary['critical']}, H={summary['high']}, "
        f"M={summary['medium']}, L={summary['low']}"
    )

    return render_template("index.html", summary=summary)
''').lstrip()

path.write_text(before + body_new + "\n\n" + after, encoding="utf-8")
print("[OK] fixed index route")
PY
