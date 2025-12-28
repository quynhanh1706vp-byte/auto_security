#!/usr/bin/env bash
set -euo pipefail

APP="app.py"
echo "[i] APP = $APP"

if [ ! -f "$APP" ]; then
  echo "[ERR] Không tìm thấy $APP"
  exit 1
fi

python3 - "$APP" <<'PY'
import sys, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

if "/api/top_risks_any" in data:
    print("[INFO] Đã có route /api/top_risks_any, bỏ qua.")
    sys.exit(0)

block = '''
from pathlib import Path as _PathTop
import json as _jsonTop

def _get_last_run_with_report():
    root = _PathTop("/home/test/Data/SECURITY_BUNDLE/out")
    if not root.is_dir():
        return None
    candidates = []
    for p in root.glob("RUN_*"):
        report = p / "report" / "summary_unified.json"
        if report.is_file():
            try:
                mtime = report.stat().st_mtime
            except Exception:
                mtime = p.stat().st_mtime
            candidates.append((mtime, p))
    if not candidates:
        return None
    candidates.sort(reverse=True)
    _, run_dir = candidates[0]
    return run_dir

@app.route("/api/top_risks_any", methods=["GET"])
def api_top_risks_any():
    """Top Critical/High findings từ findings_unified.json của RUN_* mới nhất."""
    run_dir = _get_last_run_with_report()
    if run_dir is None:
        return jsonify([])
    fpath = run_dir / "report" / "findings_unified.json"
    if not fpath.is_file():
        return jsonify([])
    try:
        raw = fpath.read_text(encoding="utf-8")
        data = _jsonTop.loads(raw)
    except Exception as e:
        print("[ERR][TOP_RISKS_ANY] Lỗi đọc findings_unified.json:", e)
        return jsonify([])
    weights = {"CRITICAL": 2, "HIGH": 1}
    items = []
    if isinstance(data, list):
        for it in data:
            sev = str(it.get("severity", "")).upper()
            if sev not in weights:
                continue
            items.append({
                "severity": sev,
                "tool": it.get("tool") or "",
                "rule": it.get("rule") or it.get("check_id") or "",
                "location": it.get("location") or it.get("path") or "",
            })
    items.sort(key=lambda x: (-weights[x["severity"]], x["tool"], x["rule"], x["location"]))
    return jsonify(items[:10])
'''

marker = 'if __name__ == "__main__":'
if marker in data:
    head, tail = data.split(marker, 1)
    new = head.rstrip() + "\n\n" + textwrap.dedent(block) + "\n\n" + marker + tail
else:
    new = data.rstrip() + "\n\n" + textwrap.dedent(block) + "\n"

path.write_text(new, encoding="utf-8")
print("[OK] Đã thêm block /api/top_risks_any vào app.py")
PY
