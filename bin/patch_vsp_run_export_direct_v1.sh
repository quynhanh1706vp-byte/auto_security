#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
P="$ROOT/vsp_demo_app.py"

if [ ! -f "$P" ]; then
  echo "[ERR] Không tìm thấy $P"
  exit 1
fi

BACKUP="${P}.bak_run_export_$(date +%Y%m%d_%H%M%S)"
cp "$P" "$BACKUP"
echo "[PATCH] Backup: $BACKUP"

python - "$P" << 'PY'
import sys, textwrap, pathlib, re

p = pathlib.Path(sys.argv[1])
txt = p.read_text(encoding="utf-8")

# Xoá block cũ nếu có (được đánh dấu bằng BEGIN/END)
txt = re.sub(
    r"#\s*VSP_RUN_EXPORT_DIRECT_V1_BEGIN.*?#\s*VSP_RUN_EXPORT_DIRECT_V1_END\s*",
    "",
    txt,
    flags=re.S | re.M,
)

block = textwrap.dedent("""
# VSP_RUN_EXPORT_DIRECT_V1_BEGIN
from flask import send_file, request, jsonify, render_template
import io, json, zipfile, subprocess, shutil
from pathlib import Path

@app.route("/api/vsp/run_export_v3", methods=["GET"])
def vsp_run_export_v3():
    \"""
    Direct export HTML/PDF/ZIP cho 1 RUN_...
    - fmt=html -> RUN_..._vsp_report.html
    - fmt=pdf  -> RUN_..._vsp_report.pdf (cần wkhtmltopdf)
    - fmt=zip  -> RUN_..._vsp_full_bundle.zip (nguyên thư mục out/RUN_...)
    \"""
    run_id = request.args.get("run_id")
    fmt = (request.args.get("fmt") or "html").lower()

    if not run_id:
        return jsonify(ok=False, error="Missing run_id"), 400

    # ROOT = thư mục SECURITY_BUNDLE, out chứa RUN_VSP_FULL_EXT_*
    root = Path(__file__).resolve().parents[1] / "out"
    run_dir = root / run_id

    if not run_dir.is_dir():
        return jsonify(ok=False, error=f"Run directory not found: {run_dir}"), 404

    summary_path = run_dir / "report" / "summary_unified.json"
    if not summary_path.is_file():
        return jsonify(ok=False, error="report/summary_unified.json not found"), 500

    # Đọc summary 1 lần
    with summary_path.open("r", encoding="utf-8") as f:
        summary = json.load(f)

    if fmt == "html":
        html = render_template(
            "vsp_run_report_cio_v3.html",
            run_id=run_id,
            summary=summary,
        )
        return app.response_class(
            html,
            mimetype="text/html",
            headers={
                "Content-Disposition": f"attachment; filename={run_id}_vsp_report.html"
            },
        )

    if fmt == "pdf":
        # Yêu cầu wkhtmltopdf
        if shutil.which("wkhtmltopdf") is None:
            return jsonify(ok=False, error="wkhtmltopdf not installed"), 500

        html = render_template(
            "vsp_run_report_cio_v3.html",
            run_id=run_id,
            summary=summary,
        )
        pdf_bytes = subprocess.check_output(
            ["wkhtmltopdf", "-", "-"],
            input=html.encode("utf-8"),
        )
        return send_file(
            io.BytesIO(pdf_bytes),
            mimetype="application/pdf",
            as_attachment=True,
            download_name=f"{run_id}_vsp_report.pdf",
        )

    if fmt == "zip":
        buf = io.BytesIO()
        # Zip nguyên thư mục RUN_... (giữ luôn tên RUN_... ở root trong zip)
        with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as z:
            for path in run_dir.rglob("*"):
                if path.is_file():
                    # entry path: RUN_.../path/to/file
                    arcname = path.relative_to(run_dir.parent)
                    z.write(path, arcname)
        buf.seek(0)
        return send_file(
            buf,
            mimetype="application/zip",
            as_attachment=True,
            download_name=f"{run_id}_vsp_full_bundle.zip",
        )

    return jsonify(ok=False, error=f"Unsupported fmt={fmt}"), 400
# VSP_RUN_EXPORT_DIRECT_V1_END
""")

# Chèn block trước if __name__ == "__main__" nếu có
m = re.search(r'^if __name__ == ["\']__main__["\']:\s*$', txt, flags=re.M)
if m:
    idx = m.start()
    txt = txt[:idx] + "\\n" + block + "\\n\\n" + txt[idx:]
else:
    txt = txt + "\\n" + block + "\\n"

p.write_text(txt, encoding="utf-8")
print("[PATCH] Đã chèn block VSP_RUN_EXPORT_DIRECT_V1 vào", p)
PY

chmod +x bin/patch_vsp_run_export_direct_v1.sh
echo "[PATCH] Done. Chạy: bin/patch_vsp_run_export_direct_v1.sh"
