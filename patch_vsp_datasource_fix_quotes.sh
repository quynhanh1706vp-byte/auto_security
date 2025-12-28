#!/usr/bin/env bash
set -euo pipefail

PY_FILE="vsp_demo_app.py"

echo "[i] Backup file gốc..."
cp "$PY_FILE" "${PY_FILE}.bak.datasource_fix_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path

path = Path("vsp_demo_app.py")
text = path.read_text(encoding="utf-8")

marker = "# ======= OVERRIDE /api/vsp/datasource"
if marker in text:
    # Cắt bỏ mọi thứ từ marker trở đi, giữ lại phần code trước đó
    text = text.split(marker)[0].rstrip()

block = '''
# ======= OVERRIDE /api/vsp/datasource – CLEAN VERSION (NO RUN_ROOT) =======
@app.route("/api/vsp/datasource", methods=["GET"])
def api_vsp_datasource():
    """Data Source cho tab Data:
    - Tự động tìm RUN_* mới nhất trong ./out
    - Lấy file report/findings_unified.json
    - Trả JSON: ok, run_id, summary.total, rows
    """
    import json
    from pathlib import Path as _Path

    try:
        root = _Path(__file__).resolve().parents[1]
        out_dir = root / "out"

        if not out_dir.is_dir():
            return jsonify({
                "ok": False,
                "error": f"Out dir not found: {out_dir}"
            }), 404

        # Lấy list RUN_* theo mtime mới nhất
        run_dirs = sorted(
            [p for p in out_dir.iterdir() if p.is_dir() and p.name.startswith("RUN_")],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )

        run_dir = None
        findings_path = None
        for rd in run_dirs:
            cand = rd / "report" / "findings_unified.json"
            if cand.is_file():
                run_dir = rd
                findings_path = cand
                break

        if run_dir is None or findings_path is None:
            return jsonify({
                "ok": False,
                "error": "No RUN_* with report/findings_unified.json found"
            }), 404

        with findings_path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)

        # Chuẩn hóa rows
        if isinstance(data, dict) and "rows" in data:
            rows = data["rows"]
        elif isinstance(data, list):
            rows = data
        else:
            rows = []

        summary = {
            "total": len(rows),
        }

        return jsonify({
            "ok": True,
            "run_id": run_dir.name,
            "summary": summary,
            "rows": rows,
        })
    except Exception as exc:
        app.logger.exception("[VSP][DATASOURCE] Error while building datasource.")
        return jsonify({
            "ok": False,
            "error": str(exc),
        }), 500
'''

path.write_text(text + block + "\n", encoding="utf-8")
PY

echo "[OK] Đã fix lại /api/vsp/datasource với docstring chuẩn."
