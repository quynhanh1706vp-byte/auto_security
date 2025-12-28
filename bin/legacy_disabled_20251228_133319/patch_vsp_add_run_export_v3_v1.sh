#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$UI_ROOT/vsp_demo_app.py"
BACKUP="$APP.bak_run_export_v3_$(date +%Y%m%d_%H%M%S)"

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

if "/api/vsp/run_export_v3" in src:
    print("[INFO] Route /api/vsp/run_export_v3 đã tồn tại, không chèn thêm.")
else:
    snippet = textwrap.dedent('''
    @app.route("/api/vsp/run_export_v3")
    def vsp_run_export_v3():
        """Direct export HTML/ZIP cho 1 run – chạy ngay trên UI gateway (8910)."""
        from pathlib import Path
        import zipfile
        from flask import request, jsonify, send_file

        run_id = (request.args.get("run_id") or "").strip()
        fmt = (request.args.get("fmt") or "html").strip().lower()

        if not run_id:
            return jsonify(ok=False, error="Missing run_id"), 400

        ui_root = Path(__file__).resolve().parent
        bundle_root = ui_root.parent
        out_root = bundle_root / "out"
        run_dir = out_root / run_id

        if not run_dir.is_dir():
            return jsonify(ok=False, error=f"Run dir not found: {run_dir}"), 404

        report_dir = run_dir / "report"

        if fmt == "html":
            # Ưu tiên report CIO, fallback nếu không có
            candidates = [
                report_dir / "vsp_run_report_cio_v3.html",
                report_dir / "vsp_run_report_cio_v2.html",
                report_dir / "vsp_run_report_cio_v1.html",
            ]
            html_path = None
            for p in candidates:
                if p.is_file():
                    html_path = p
                    break

            if html_path is None:
                summary = report_dir / "summary_unified.json"
                if summary.is_file():
                    # fallback: trả summary JSON
                    return send_file(
                        summary,
                        mimetype="application/json",
                        as_attachment=False,
                    )
                return jsonify(ok=False, error="Không tìm thấy report HTML cho run này."), 404

            return send_file(
                html_path,
                mimetype="text/html",
                as_attachment=False,
                download_name=html_path.name,
            )

        if fmt == "zip":
            export_name = f"{run_id}_export_v3.zip"
            zip_path = run_dir / export_name

            def add_if_exists(zf, rel_path: Path):
                p = run_dir / rel_path
                if p.is_file():
                    zf.write(p, arcname=str(rel_path))

            with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
                # Core reports
                add_if_exists(zf, Path("report") / "summary_unified.json")
                add_if_exists(zf, Path("report") / "findings_unified.json")
                add_if_exists(zf, Path("report") / "vsp_run_report_cio_v3.html")
                add_if_exists(zf, Path("report") / "vsp_run_report_cio_v2.html")
                add_if_exists(zf, Path("report") / "vsp_run_report_cio_v1.html")

                # SBOM / license nếu có
                add_if_exists(zf, Path("sbom") / "sbom.json")
                add_if_exists(zf, Path("license") / "license_report.json")

            return send_file(
                zip_path,
                mimetype="application/zip",
                as_attachment=True,
                download_name=export_name,
            )

        return jsonify(ok=False, error=f"Unsupported fmt={fmt}"), 400
    ''')

    # Chèn route mới vào cuối file cho an toàn
    src = src.rstrip() + "\n\n" + snippet + "\n"
    app_path.write_text(src, encoding="utf-8")
    print("[PATCH] Đã thêm route /api/vsp/run_export_v3 vào vsp_demo_app.py")
PY

echo "[DONE] Patch vsp_add_run_export_v3_v1 hoàn tất."
