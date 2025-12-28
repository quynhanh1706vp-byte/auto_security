#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy vsp_demo_app.py: $FILE" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${FILE}.bak_run_fullscan_api_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup vsp_demo_app.py thành: $BACKUP"

FILE="$FILE" python - << 'PY'
import os, pathlib

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

if "/api/vsp/run_fullscan_v1" in txt:
    print("[INFO] Route /api/vsp/run_fullscan_v1 đã tồn tại, không patch.")
else:
    BLOCK = r"""

@app.route("/api/vsp/run_fullscan_v1", methods=["POST"])
def vsp_run_fullscan_v1():
    \"\"\"Stub API: nhận yêu cầu Run full scan từ UI.

    Payload dạng:
    {
      "source_root": "/path/or/null",
      "target_url": "https://app.or.null",
      "profile": "FULL_EXT",
      "mode": "EXT_ONLY | URL_ONLY | FULL_EXT"
    }
    \"\"\"
    from flask import request, jsonify

    data = request.get_json(silent=True, force=True) or {}
    source_root = (data.get("source_root") or "").strip() or None
    target_url  = (data.get("target_url")  or "").strip() or None
    profile     = (data.get("profile")     or "FULL_EXT").strip()
    mode        = (data.get("mode")        or "").strip() or "FULL_EXT"

    print("[VSP_RUN_FULLSCAN_API] payload:",
          {"source_root": source_root, "target_url": target_url,
           "profile": profile, "mode": mode},
          flush=True)

    # TODO: Ở V1: chỉ log + trả ok=true để UI không báo lỗi.
    # V1.5: map sang script thật (run_full_ext, run_kics, v.v.)
    return jsonify({
        "ok": True,
        "source_root": source_root,
        "target_url": target_url,
        "profile": profile,
        "mode": mode
    })
"""

    txt = txt.rstrip() + "\n" + BLOCK
    path.write_text(txt, encoding="utf-8")
    print("[OK] Đã append stub vsp_run_fullscan_v1 vào", path)
PY
