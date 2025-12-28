#!/usr/bin/env bash
set -euo pipefail

APP_PY="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"

echo "[PATCH] Sửa lại block VSP_RUN_EXPORT_DIRECT_V1 cho sạch syntax"

python - << 'PY'
from pathlib import Path

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8")

marker = "# === VSP_RUN_EXPORT_DIRECT_V1 ==="

# Lấy phần trước marker (giữ nguyên), phần sau sẽ được thay toàn bộ
if marker in txt:
    prefix = txt.split(marker)[0]
else:
    prefix = txt
    # nếu chưa có marker thì thêm mới ở cuối
    prefix = prefix.rstrip() + "\n\n"

block = '''# === VSP_RUN_EXPORT_DIRECT_V1 ===
from flask import request, send_file, render_template, make_response, jsonify

@app.route("/api/vsp/run_export_v3", methods=["GET"])
def vsp_run_export_v3_direct():
    """
    Direct export HTML/PDF/ZIP cho 1 run – chạy trực tiếp trên UI gateway (8910).
    """
    from pathlib import Path
    import json, io, zipfile, subprocess, shutil

    ROOT = Path(__file__).resolve().parents[1]   # /home/test/Data/SECURITY_BUNDLE
    OUT_DIR = ROOT / "out"

    run_id = (request.args.get("run_id") or "").strip()
    fmt = (request.args.get("fmt") or "html").lower()

    if not run_id:
        return jsonify(ok=False, error="Missing run_id"), 400

    run_dir = OUT_DIR / run_id
    if not run_dir.is_dir():
        return jsonify(ok=False, error=f"Run dir not found: {run_dir}"), 404

    report_dir = run_dir / "report"
    summary_path = report_dir / "summary_unified.json"

    if summary_path.is_file():
        try:
            summary = json.loads(summary_path.read_text(encoding="utf-8"))
        except Exception:
            summary = {}
    else:
        summary = {}

    summary.setdefault("run_id", run_id)
    summary.setdefault("total_findings", 0)
    summary.setdefault("security_score", None)
    summary.setdefault("by_severity", {})
    summary.setdefault("by_tool", {})

    # HTML luôn generate trước
    html = render_template("vsp_run_report_cio_v3.html",
                           run_id=run_id,
                           summary=summary)

    # 1) HTML
    if fmt == "html":
        resp = make_response(html)
        resp.headers["Content-Type"] = "text/html; charset=utf-8"
        filename = f"{run_id}_vsp_report.html"
        if request.args.get("inline") == "1":
            # hiển thị trực tiếp
            pass
        else:
            resp.headers["Content-Disposition"] = f'attachment; filename="{filename}"'
        return resp

    # 2) PDF – dùng wkhtmltopdf nếu có
    if fmt == "pdf":
        if not shutil.which("wkhtmltopdf"):
            return jsonify(ok=False,
                           error="wkhtmltopdf not installed on server – cannot build PDF"), 500
        try:
            proc = subprocess.run(
                ["wkhtmltopdf", "-q", "-", "-"],
                input=html.encode("utf-8"),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            if proc.returncode != 0:
                return jsonify(
                    ok=False,
                    error="wkhtmltopdf failed",
                    stderr=proc.stderr.decode("utf-8", errors="ignore"),
                ), 500

            pdf_bytes = proc.stdout
            buf = io.BytesIO(pdf_bytes)
            buf.seek(0)
            return send_file(
                buf,
                mimetype="application/pdf",
                as_attachment=True,
                download_name=f"{run_id}_vsp_report.pdf",
            )
        except Exception as ex:
            return jsonify(ok=False, error=f"PDF export error: {ex}"), 500

    # 3) ZIP – bundle full run dir (evidence)
    if fmt == "zip":
        mem = io.BytesIO()
        with zipfile.ZipFile(mem, "w", compression=zipfile.ZIP_DEFLATED) as zf:
            for pth in run_dir.rglob("*"):
                if pth.is_file():
                    arc = pth.relative_to(run_dir)
                    zf.write(pth, arcname=str(arc))
        mem.seek(0)
        return send_file(
            mem,
            mimetype="application/zip",
            as_attachment=True,
            download_name=f"{run_id}_vsp_full_bundle.zip",
        )

    return jsonify(ok=False, error=f"Unsupported fmt: {fmt}"), 400

'''

new_txt = prefix.rstrip() + "\n\n" + block + "\n"
backup = p.with_suffix(p.suffix + ".bak_run_export_direct_fix")
backup.write_text(txt, encoding="utf-8")
p.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã ghi lại block direct export (backup ->", backup.name, ")")
PY

echo "[PATCH] Done."
