#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
FILE="$ROOT/vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE"
  exit 1
fi

echo "[i] Backup file gốc..."
cp "$FILE" "${FILE}.bak_ds_fix_$(date +%Y%m%d_%H%M%S)"

python3 - << 'PY'
from pathlib import Path
import re
import textwrap

path = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
text = path.read_text(encoding="utf-8")

# 1) Xóa TẤT CẢ các block @app.route("/api/vsp/datasource"... cũ
pattern = r'@app\.route\("/api/vsp/datasource"[\s\S]+?(?=^@app\.route\("|^if __name__ == "__main__":|$)'
clean_text, n = re.subn(pattern, "", text, flags=re.MULTILINE)
print(f"[OK] Đã xoá {n} block api_vsp_datasource cũ.")

# 2) Chuẩn bị block mới V4
new_block = textwrap.dedent("""
@app.route("/api/vsp/datasource", methods=["GET"])
def api_vsp_datasource():
    \"""
    Unified findings cho tab Data Source.

    Response:
      - ok: bool
      - run_id: RUN_...
      - summary: { total, severity_counts, tool_counts }
      - severity_chart: { labels, data }
      - tools_chart: { labels, data }
      - rows: list cho table
      - findings: raw findings_unified.json
    Optional query: run_id=<RUN_ID>
    \"""
    from collections import Counter  # import local để khỏi sửa phần header

    base = RUN_ROOT
    run_id = request.args.get("run_id") or None
    run_dir = None

    # Nếu có run_id thì ưu tiên dùng
    if run_id:
        cand = base / run_id
        if cand.is_dir():
            run_dir = cand

    # Nếu không có hoặc không tồn tại -> lấy RUN_* mới nhất
    if run_dir is None:
        candidates = sorted(
            [p for p in base.glob("RUN_*") if p.is_dir()],
            key=lambda p: p.name,
            reverse=True,
        )
        if candidates:
            run_dir = candidates[0]

    if run_dir is None:
        return jsonify({
            "ok": False,
            "error": "No RUN_* folder found under RUN_ROOT.",
            "rows": [],
            "findings": [],
            "summary": {
                "total": 0,
                "severity_counts": {},
                "tool_counts": {}
            },
            "severity_chart": {"labels": [], "data": []},
            "tools_chart": {"labels": [], "data": []}
        }), 404

    findings_path = run_dir / "report" / "findings_unified.json"
    if not findings_path.is_file():
        app.logger.warning(
            "[VSP][DATASOURCE] missing findings_unified.json in %s", run_dir
        )
        return jsonify({
            "ok": False,
            "error": f"Missing findings_unified.json in {run_dir}",
            "rows": [],
            "findings": [],
            "summary": {
                "total": 0,
                "severity_counts": {},
                "tool_counts": {}
            },
            "severity_chart": {"labels": [], "data": []},
            "tools_chart": {"labels": [], "data": []}
        }), 404

    try:
        raw = findings_path.read_text(encoding="utf-8")
        data = json.loads(raw)
    except Exception as exc:
        app.logger.error(
            "[VSP][DATASOURCE] cannot parse findings_unified.json in %s: %s",
            run_dir,
            exc,
        )
        return jsonify({
            "ok": False,
            "error": f"Cannot parse findings_unified.json: {exc}",
            "rows": [],
            "findings": [],
            "summary": {
                "total": 0,
                "severity_counts": {},
                "tool_counts": {}
            },
            "severity_chart": {"labels": [], "data": []},
            "tools_chart": {"labels": [], "data": []}
        }), 500

    if not isinstance(data, list):
        app.logger.error(
            "[VSP][DATASOURCE] findings_unified.json is not a list in %s", run_dir
        )
        return jsonify({
            "ok": False,
            "error": "findings_unified.json must be a list of findings.",
            "rows": [],
            "findings": [],
            "summary": {
                "total": 0,
                "severity_counts": {},
                "tool_counts": {}
            },
            "severity_chart": {"labels": [], "data": []},
            "tools_chart": {"labels": [], "data": []}
        }), 500

    sev_counter = Counter()
    tool_counter = Counter()

    rows = []
    findings_raw = []

    for idx, item in enumerate(data):
        if not isinstance(item, dict):
            continue

        sev = (item.get("severity") or "INFO").upper()
        tool = (item.get("tool") or "unknown").lower()
        rule = item.get("rule_id") or item.get("rule") or ""
        file_path = item.get("file") or ""
        line_no = item.get("line") or 0
        message = item.get("message") or item.get("description") or ""
        cwe = item.get("cwe") or item.get("cve") or ""

        sev_counter[sev] += 1
        tool_counter[tool] += 1

        findings_raw.append(item)

        rows.append({
            "id": idx + 1,
            "severity": sev,
            "tool": tool,
            "rule": rule,
            "file": file_path,
            "line": line_no,
            "message": message,
            "cwe": cwe
        })

    sev_labels = sorted(sev_counter.keys())
    sev_data = [sev_counter[s] for s in sev_labels]

    top_tools_sorted = sorted(tool_counter.items(), key=lambda kv: kv[1], reverse=True)
    tool_labels = [t for t, _ in top_tools_sorted]
    tool_data = [c for _, c in top_tools_sorted]

    summary = {
        "total": len(rows),
        "severity_counts": dict(sev_counter),
        "tool_counts": dict(tool_counter)
    }

    app.logger.info(
        "[VSP][DATASOURCE] run=%s total_rows=%d",
        run_dir.name,
        len(rows)
    )

    return jsonify({
        "ok": True,
        "run_id": run_dir.name,
        "summary": summary,
        "severity_counts": dict(sev_counter),
        "tool_counts": dict(tool_counter),
        "severity_chart": {
            "labels": sev_labels,
            "data": sev_data
        },
            "tools_chart": {
            "labels": tool_labels,
            "data": tool_data
        },
        "rows": rows,
        "findings": findings_raw
    })
""").strip() + "\n\n"

# 3) Chèn block mới trước dòng if __name__ == "__main__":
marker = 'if __name__ == "__main__":'
idx = clean_text.rfind(marker)
if idx == -1:
    new_text = clean_text + "\n\n" + new_block
else:
    new_text = clean_text[:idx] + "\n\n" + new_block + clean_text[idx:]

path.write_text(new_text, encoding="utf-8")
print("[DONE] Đã ghi lại vsp_demo_app.py với api_vsp_datasource mới.")
PY

echo "[DONE] patch_vsp_datasource_fix.sh hoàn tất."
