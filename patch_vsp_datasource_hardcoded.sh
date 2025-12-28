#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
FILE="$ROOT/vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy $FILE"
  exit 1
fi

echo "[i] Backup file gốc..."
cp "$FILE" "${FILE}.bak_ds_hard_$(date +%Y%m%d_%H%M%S)"

echo "[i] Append api_vsp_datasource (HARDCODED) vào cuối file..."

cat >> "$FILE" << 'PYEOF'

# ======= VSP Data Source API – HARDCODED OUT DIR =======
@app.route("/api/vsp/datasource", methods=["GET"])
def api_vsp_datasource():
    """
    Data Source cho VSP – đọc findings_unified.json từ out/RUN_* mới nhất.

    Response:
      - ok: bool
      - run_id: RUN_...
      - summary: { total, severity_counts, tool_counts }
      - severity_chart: { labels, data }
      - tools_chart: { labels, data }
      - rows: list cho table
      - findings: raw findings_unified.json
      - error: string nếu ok = False
    """
    from collections import Counter
    from pathlib import Path
    import json

    base = Path("/home/test/Data/SECURITY_BUNDLE/out")

    try:
        run_id = request.args.get("run_id") or None
        run_dir = None

        # 1) Nếu có run_id thì ưu tiên dùng
        if run_id:
            cand = base / run_id
            if cand.is_dir():
                run_dir = cand

        # 2) Nếu không có hoặc không tồn tại -> lấy RUN_* mới nhất
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
                "error": "No RUN_* folder found under /home/test/Data/SECURITY_BUNDLE/out.",
                "run_id": None,
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
            return jsonify({
                "ok": False,
                "error": f"Missing findings_unified.json in {run_dir}",
                "run_id": run_dir.name,
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

        raw = findings_path.read_text(encoding="utf-8")
        data = json.loads(raw)

        if not isinstance(data, list):
            return jsonify({
                "ok": False,
                "error": "findings_unified.json must be a list of findings.",
                "run_id": run_dir.name,
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

        # Build chart data
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
            "findings": findings_raw,
            "error": ""
        })

    except Exception as exc:
        # Bắt mọi lỗi còn lại để không trả HTML 500 nữa
        app.logger.error("[VSP][DATASOURCE] unexpected error: %s", exc)
        return jsonify({
            "ok": False,
            "error": str(exc),
            "run_id": None,
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
# ======= END VSP Data Source API – HARDCODED OUT DIR =======

PYEOF

echo "[OK] Đã append api_vsp_datasource HARDCODED vào $FILE"
