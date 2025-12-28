#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$UI_ROOT/vsp_demo_app.py"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERR] Không tìm thấy $TARGET"
  exit 1
fi

BACKUP="${TARGET}.bak_run_export_dedupe_v3_$(date +%Y%m%d_%H%M%S)"
cp "$TARGET" "$BACKUP"
echo "[BACKUP] $TARGET -> $BACKUP"

export VSP_DEMO_APP="$TARGET"

python - << 'PY'
import os, pathlib

target = pathlib.Path(os.environ["VSP_DEMO_APP"])
txt = target.read_text(encoding="utf-8")

lines = txt.splitlines()
clean_lines = []

i = 0
removed_route_blocks = 0
removed_def_blocks = 0

while i < len(lines):
    line = lines[i]
    stripped = line.lstrip()

    # Bỏ block bắt đầu từ @app.route("/api/vsp/run_export_v3", ...) ...
    if '@app.route("/api/vsp/run_export_v3"' in line or "@app.route('/api/vsp/run_export_v3'" in line:
        removed_route_blocks += 1
        i += 1
        # skip cho đến khi gặp decorator khác hoặc if __main__
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    # Bỏ block def vsp_run_export_v3(...) nếu còn sót
    if stripped.startswith('def vsp_run_export_v3('):
        removed_def_blocks += 1
        i += 1
        while i < len(lines):
            s = lines[i].lstrip()
            if s.startswith('@app.route(') or s.startswith('if __name__ == "__main__":'):
                break
            i += 1
        continue

    clean_lines.append(line)
    i += 1

print(f"[INFO] Removed {removed_route_blocks} route block(s) and {removed_def_blocks} def block(s) for run_export_v3")

cleaned_txt = "\n".join(clean_lines) + "\n"

marker = 'if __name__ == "__main__":'
idx = cleaned_txt.find(marker)
if idx == -1:
    raise SystemExit("Không tìm thấy if __name__ == '__main__' trong vsp_demo_app.py")

before = cleaned_txt[:idx]
after = cleaned_txt[idx:]

block = '''
@app.route("/api/vsp/run_export_v3", methods=["GET"])
def vsp_run_export_v3():
    """
    Direct export HTML/ZIP/PDF/CSV cho 1 run - chạy trên UI gateway (8910).
    """
    from flask import request, jsonify, send_file
    import os, io, zipfile, json

    run_id = (request.args.get("run_id") or "").strip()
    fmt = (request.args.get("fmt") or "html").strip().lower()

    if not run_id:
        return jsonify({"ok": False, "error": "Missing run_id"}), 400

    # Thư mục out gốc: ưu tiên env VSP_OUT_ROOT, fallback ../out cạnh ui/
    base_out = os.environ.get("VSP_OUT_ROOT")
    if not base_out:
        base_out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "out"))

    run_dir = os.path.join(base_out, run_id)
    if not os.path.isdir(run_dir):
        return jsonify({"ok": False, "error": f"Run dir not found: {run_dir}"}), 404

    report_dir = os.path.join(run_dir, "report")

    # HTML export
    if fmt == "html":
        candidates = [
            os.path.join(report_dir, "vsp_run_report_cio_v3.html"),
            os.path.join(report_dir, "vsp_run_report_cio_v2.html"),
            os.path.join(report_dir, "vsp_run_report_cio.html"),
            os.path.join(report_dir, "run_report.html"),
        ]
        for path in candidates:
            if os.path.isfile(path):
                return send_file(
                    path,
                    mimetype="text/html",
                    as_attachment=False,
                    download_name=os.path.basename(path),
                )

        # fallback – render summary_unified.json thành HTML đơn giản
        summary_path = os.path.join(report_dir, "summary_unified.json")
        summary = {}
        if os.path.isfile(summary_path):
            try:
                with open(summary_path, "r", encoding="utf-8") as f:
                    summary = json.load(f)
            except Exception:
                summary = {}

        body = json.dumps(
            summary or {"note": "No summary_unified.json found"},
            indent=2,
            ensure_ascii=False,
        )

        html = (
            "<html><head><meta charset='utf-8'>"
            "<title>VSP run {run_id}</title></head><body>"
            "<h1>VSP run {run_id}</h1>"
            "<pre>{body}</pre>"
            "</body></html>"
        ).format(run_id=run_id, body=body)

        return html

    # CSV export
    if fmt == "csv":
        csv_path = os.path.join(report_dir, "findings_unified.csv")
        if os.path.isfile(csv_path):
            return send_file(
                csv_path,
                mimetype="text/csv",
                as_attachment=True,
                download_name=f"{run_id}_findings.csv",
            )
        return jsonify({"ok": False, "error": "findings_unified.csv not found"}), 404

    # ZIP export
    if fmt == "zip":
        if not os.path.isdir(report_dir):
            return jsonify({"ok": False, "error": "report dir not found"}), 404

        mem = io.BytesIO()
        with zipfile.ZipFile(mem, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(report_dir):
                for fn in files:
                    full = os.path.join(root, fn)
                    rel = os.path.relpath(full, run_dir)
                    zf.write(full, rel)

        mem.seek(0)
        return send_file(
            mem,
            mimetype="application/zip",
            as_attachment=True,
            download_name=f"{run_id}_report.zip",
        )

    # PDF export (nếu có sẵn file PDF trong report/)
    if fmt == "pdf":
        if os.path.isdir(report_dir):
            for name in os.listdir(report_dir):
                if name.lower().endswith(".pdf"):
                    path = os.path.join(report_dir, name)
                    return send_file(
                        path,
                        mimetype="application/pdf",
                        as_attachment=True,
                        download_name=name,
                    )
        return jsonify({"ok": False, "error": "PDF report not found"}), 404

    return jsonify({"ok": False, "error": f"Unsupported fmt={fmt}"}), 400
'''.lstrip("\n")

new_txt = before.rstrip() + "\n\n" + block + "\n\n" + after.lstrip()
target.write_text(new_txt, encoding="utf-8")
print("[PATCH] Đã chuẩn hoá 1 route duy nhất /api/vsp/run_export_v3")
PY

echo "[OK] Done."
