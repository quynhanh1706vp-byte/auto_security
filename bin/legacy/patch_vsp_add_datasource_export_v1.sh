#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"
BACKUP="$APP.bak_ds_export_v1_$(date +%Y%m%d_%H%M%S)"

echo "[INFO] UI_ROOT = $UI_ROOT"
echo "[INFO] APP     = $APP"
cp "$APP" "$BACKUP"
echo "[BACKUP] $APP -> $BACKUP"

cd "$UI_ROOT"

python - << 'PY'
from pathlib import Path
import textwrap

app_path = Path("vsp_demo_app.py")
src = app_path.read_text(encoding="utf-8")

if "/api/vsp/datasource_export_v1" in src:
    print("[INFO] Route /api/vsp/datasource_export_v1 đã tồn tại, bỏ qua.")
else:
    snippet = textwrap.dedent('''
    @app.route("/api/vsp/datasource_export_v1")
    def vsp_datasource_export_v1():
        """Export findings_unified cho Data Source – V1: JSON + CSV.

        - Nếu có run_dir trong query thì dùng run_dir đó.
        - Nếu không, dùng latest_run_id từ /api/vsp/dashboard_v3.
        """

        from flask import request, jsonify, send_file
        import json
        import csv
        import tempfile

        ui_root = Path(__file__).resolve().parent
        bundle_root = ui_root.parent
        out_root = bundle_root / "out"

        fmt = (request.args.get("fmt") or "json").strip().lower()
        run_dir_arg = (request.args.get("run_dir") or "").strip()

        run_dir = None

        if run_dir_arg:
            run_dir = Path(run_dir_arg)
        else:
            # Lấy latest_run_id từ dashboard_v3
            try:
                with app.test_client() as c:
                    r = c.get("/api/vsp/dashboard_v3")
                    if r.is_json:
                        data = r.get_json() or {}
                    else:
                        data = {}
                latest_run_id = data.get("latest_run_id")
                if latest_run_id:
                    run_dir = out_root / latest_run_id
            except Exception as e:
                return jsonify(ok=False, error=f"Không lấy được latest_run_id: {e}"), 500

        if run_dir is None:
            return jsonify(ok=False, error="Không xác định được run_dir"), 400

        if not run_dir.is_dir():
            return jsonify(ok=False, error=f"Run dir not found: {run_dir}"), 404

        report_dir = run_dir / "report"
        findings_path = report_dir / "findings_unified.json"

        if not findings_path.is_file():
            return jsonify(ok=False, error=f"Không tìm thấy findings_unified.json trong {report_dir}"), 404

        if fmt == "json":
            # Trả thẳng file JSON
            return send_file(
                findings_path,
                mimetype="application/json",
                as_attachment=True,
                download_name=f"{run_dir.name}_findings_unified.json",
            )

        if fmt == "csv":
            # Convert JSON -> CSV với các cột chuẩn
            try:
                items = json.loads(findings_path.read_text(encoding="utf-8"))
            except Exception as e:
                return jsonify(ok=False, error=f"Không đọc được JSON: {e}"), 500

            if not isinstance(items, list):
                return jsonify(ok=False, error="findings_unified.json không phải là list"), 500

            # Giữ schema giống Data Source ext columns
            fieldnames = [
                "severity",
                "tool",
                "rule",
                "path",
                "line",
                "message",
                "run",
                "cwe",
                "cve",
                "component",
                "tags",
                "fix",
            ]

            def norm_sev(s):
                if not s:
                    return ""
                up = str(s).upper()
                known = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "INFO", "TRACE"]
                return up if up in known else str(s)

            def extract_line(item):
                if "line" in item and item["line"] is not None:
                    return item["line"]
                if "line_number" in item and item["line_number"] is not None:
                    return item["line_number"]
                loc = item.get("location") or {}
                if isinstance(loc, dict) and "line" in loc:
                    return loc["line"]
                return ""

            def extract_rule(item):
                for k in ["rule_id", "rule", "check_id", "check", "rule_name", "id"]:
                    if k in item and item[k]:
                        return item[k]
                return ""

            def extract_msg(item):
                for k in ["message", "msg", "description", "title"]:
                    if k in item and item[k]:
                        return item[k]
                return ""

            def extract_run(item):
                for k in ["run_id", "run", "run_ref"]:
                    if k in item and item[k]:
                        return item[k]
                return ""

            def extract_cwe(item):
                if item.get("cwe"):
                    return item["cwe"]
                if item.get("cwe_id"):
                    return item["cwe_id"]
                if isinstance(item.get("cwe_list"), list) and item["cwe_list"]:
                    return ",".join(map(str, item["cwe_list"]))
                return ""

            def extract_cve(item):
                if item.get("cve"):
                    return item["cve"]
                for k in ["cve_list", "cves"]:
                    v = item.get(k)
                    if isinstance(v, list) and v:
                        return ",".join(map(str, v))
                return ""

            def extract_component(item):
                for k in ["component", "module", "package", "image"]:
                    if item.get(k):
                        return item[k]
                return ""

            def extract_tags(item):
                tags = item.get("tags") or item.get("labels")
                if not tags:
                    return ""
                if isinstance(tags, list):
                    return ",".join(map(str, tags))
                return str(tags)

            def extract_fix(item):
                for k in ["fix", "remediation", "recommendation"]:
                    if item.get(k):
                        return item[k]
                return ""

            tmp = tempfile.NamedTemporaryFile(mode="w+", suffix=".csv", delete=False, encoding="utf-8", newline="")
            tmp_path = Path(tmp.name)

            writer = csv.DictWriter(tmp, fieldnames=fieldnames)
            writer.writeheader()

            for it in items:
                if not isinstance(it, dict):
                    continue
                row = {
                    "severity": norm_sev(it.get("severity") or it.get("level")),
                    "tool": it.get("tool") or it.get("source") or it.get("scanner") or "",
                    "rule": extract_rule(it),
                    "path": it.get("path") or it.get("file") or it.get("location") or "",
                    "line": extract_line(it),
                    "message": extract_msg(it),
                    "run": extract_run(it),
                    "cwe": extract_cwe(it),
                    "cve": extract_cve(it),
                    "component": extract_component(it),
                    "tags": extract_tags(it),
                    "fix": extract_fix(it),
                }
                writer.writerow(row)

            tmp.flush()
            tmp.close()

            return send_file(
                tmp_path,
                mimetype="text/csv",
                as_attachment=True,
                download_name=f"{run_dir.name}_findings_unified.csv",
            )

        return jsonify(ok=False, error=f"Unsupported fmt={fmt} (chỉ hỗ trợ json|csv trong V1)"), 400
    ''')

    src = src.rstrip() + "\n\n" + snippet + "\n"
    app_path.write_text(src, encoding="utf-8")
    print("[PATCH] Đã thêm route /api/vsp/datasource_export_v1 vào vsp_demo_app.py")
PY

echo "[DONE] Patch vsp_add_datasource_export_v1 hoàn tất."
