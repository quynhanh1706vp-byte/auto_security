#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, re, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
code = path.read_text(encoding="utf-8")

# Regex: tìm block @app.route("/") ... def index(...)
pattern = re.compile(
    r'@app\.route\(\s*"/"\s*[^)]*\)\s*def\s+index\s*\([^)]*\):'
    r'[\s\S]*?'
    r'(?=\n@app\.route|\n#\s*@app\.route|\Z)',
    re.MULTILINE,
)

new_block = textwrap.dedent('''
@app.route("/", methods=["GET"])
def index():
    """
    Dashboard chính: đọc RUN_* mới nhất trong out/ và đẩy số liệu
    lên template index.html (phiên bản mới).
    """
    import json, datetime, os
    from pathlib import Path

    ROOT = Path("/home/test/Data/SECURITY_BUNDLE")
    OUT = ROOT / "out"

    total_findings = 0
    crit_count = high_count = medium_count = low_count = 0
    last_run_id = "RUN_YYYYmmdd_HHMMSS"
    last_updated = "—"

    if OUT.is_dir():
        runs = []
        for p in OUT.iterdir():
            if p.is_dir() and re.match(r"^RUN_\\d{8}_\\d{6}$", p.name):
                runs.append(p)
        runs.sort(key=lambda x: x.name)
        if runs:
            last = runs[-1]
            last_run_id = last.name
            dt = datetime.datetime.fromtimestamp(last.stat().st_mtime)
            last_updated = dt.strftime("%Y-%m-%d %H:%M:%S")

            summary = last / "summary_unified.json"
            findings = last / "findings_unified.json"

            if summary.is_file():
                try:
                    with summary.open("r", encoding="utf-8") as f:
                        data = json.load(f)
                    total_findings = (
                        data.get("total")
                        or data.get("total_findings")
                        or 0
                    )
                    sev = (
                        data.get("by_severity")
                        or data.get("severity_buckets")
                        or {}
                    )
                    crit_count = int(sev.get("CRITICAL", 0) or 0)
                    high_count = int(sev.get("HIGH", 0) or 0)
                    medium_count = int(sev.get("MEDIUM", 0) or 0)
                    low_count = (
                        int(sev.get("LOW", 0) or 0)
                        + int(sev.get("INFO", 0) or 0)
                        + int(sev.get("UNKNOWN", 0) or 0)
                    )
                except Exception as e:
                    print("[WARN] Lỗi đọc summary_unified.json:", e)

            elif findings.is_file():
                # Fallback: tự đếm từ findings_unified.json
                try:
                    from collections import Counter
                    with findings.open("r", encoding="utf-8") as f:
                        arr = json.load(f)
                    total_findings = len(arr)
                    c = Counter()
                    for item in arr:
                        sev = (item.get("severity") or item.get("sev") or "").upper()
                        c[sev] += 1
                    crit_count = c.get("CRITICAL", 0)
                    high_count = c.get("HIGH", 0)
                    medium_count = c.get("MEDIUM", 0)
                    low_count = (
                        c.get("LOW", 0)
                        + c.get("INFO", 0)
                        + c.get("UNKNOWN", 0)
                    )
                except Exception as e:
                    print("[WARN] Lỗi đọc findings_unified.json:", e)

    return render_template(
        "index.html",
        total_findings=total_findings,
        crit_count=crit_count,
        high_count=high_count,
        medium_count=medium_count,
        low_count=low_count,
        last_run_id=last_run_id,
        last_updated=last_updated,
    )
''').lstrip("\n")

if not pattern.search(code):
    print("[ERR] Không tìm thấy route '/' cũ để thay thế. Không patch được.")
    sys.exit(1)

code_new = pattern.sub(new_block + "\n\n", code)
path.write_text(code_new, encoding="utf-8")
print("[OK] Đã thay thế route '/' bằng index() mới dùng summary_unified.json.")
PY
