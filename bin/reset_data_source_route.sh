#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy app.py"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, re, os

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

marker = '@app.route("/data-source")'

if marker in text:
    # Cắt từ marker tới cuối file, thay bằng block mới
    start = text.index(marker)
    text = text[:start].rstrip() + "\n"
else:
    text = text.rstrip() + "\n\n"

block = '''

@app.route("/data-source")
def data_source():
    """Trang Data Source – cho biết SECURITY_BUNDLE đang đọc dữ liệu từ đâu."""
    from pathlib import Path
    import os
    import re

    root = Path("/home/test/Data/SECURITY_BUNDLE")
    out_dir = root / "out"

    runs = []
    run_path_map = {}

    if out_dir.is_dir():
        for p in sorted(out_dir.iterdir(), key=lambda p: p.name):
            if p.is_dir() and p.name.startswith("RUN_"):
                rid = p.name
                runs.append(rid)
                run_path_map[rid] = p

    has_data = bool(runs)

    real_runs = [r for r in runs if re.match(r"^RUN_[0-9]{8}_[0-9]{6}$", r)]

    def has_unified(rid):
        rp = run_path_map[rid]
        candidates = [
            rp / "report" / "findings_unified.json",
            rp / "report" / "findings_unified_all_tools.json",
            rp / "findings_unified.json",
            rp / "findings_unified_all_tools.json",
        ]
        return any(c.is_file() for c in candidates)

    candidates = [r for r in real_runs if has_unified(r)] or real_runs or runs

    last_run_id = candidates[-1] if candidates else None
    last_run_path = run_path_map[last_run_id] if last_run_id else None

    files = []
    tool_dirs = []

    def add_file(label, rel_path):
        if not last_run_path:
            return
        p = last_run_path / rel_path
        exists = p.is_file()
        size = p.stat().st_size if exists else 0
        files.append(
            {
                "label": label,
                "rel": rel_path,
                "path": str(p),
                "exists": exists,
                "size": size,
            }
        )

    if last_run_path:
        add_file("Unified findings (findings_unified.json)", "report/findings_unified.json")
        add_file("Unified findings – all tools", "report/findings_unified_all_tools.json")
        add_file("Summary unified (summary_unified.json)", "report/summary_unified.json")
        add_file("PM-style HTML report", "report/pm_style_report.html")
        add_file("PM-style HTML (print)", "report/pm_style_report_print.html")
        add_file("PM-style PDF", "report/pm_style_report_print.pdf")
        add_file("Simple HTML report", "report/simple_report.html")
        add_file("Checkmarx-like HTML report", "report/checkmarx_like.html")

        for sub in sorted(last_run_path.iterdir(), key=lambda p: p.name):
            if not sub.is_dir():
                continue
            if sub.name.lower() == "report":
                continue
            file_count = 0
            for _root, _dirs, fns in os.walk(sub):
                file_count += len(fns)
            tool_dirs.append(
                {
                    "name": sub.name,
                    "path": str(sub),
                    "file_count": file_count,
                }
            )

    cfg_path = root / "ui" / "tool_config.json"
    cfg_info = {
        "path": str(cfg_path),
        "exists": cfg_path.is_file(),
    }

    ds = {
        "has_data": has_data,
        "runs": runs,
        "last_run_id": last_run_id,
        "last_run_path": str(last_run_path) if last_run_path else "",
        "files": files,
        "tool_dirs": tool_dirs,
        "tool_config": cfg_info,
    }

    return render_template("data_source.html", data_source=ds)
'''

text = text.rstrip() + block + "\n"
path.write_text(text, encoding="utf-8")
print("[OK] Đã reset route /data-source, tail app.py sạch.")
PY
