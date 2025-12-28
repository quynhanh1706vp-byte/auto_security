#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/vsp_demo_app.py"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy vsp_demo_app.py: $FILE" >&2
  exit 1
fi

# 1) Khôi phục từ backup gần nhất nếu có
LATEST_BAK="$(ls -t "$UI_ROOT"/vsp_demo_app.py.bak_run_fullscan_api_* 2>/dev/null | head -n1 || true)"

if [ -n "$LATEST_BAK" ]; then
  echo "[RESTORE] Khôi phục từ backup: $LATEST_BAK"
  cp "$LATEST_BAK" "$FILE"
else
  echo "[WARN] Không tìm thấy backup vsp_demo_app.py.bak_run_fullscan_api_*, giữ nguyên file hiện tại."
fi

# 2) Chèn stub route trước 'if __name__ == "__main__":'
FILE="$FILE" python - << 'PY'
import os, pathlib, sys

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

marker = 'if __name__ == "__main__":'

if marker not in txt:
    print("[ERR] Không tìm thấy block 'if __name__ == \"__main__\"' trong vsp_demo_app.py", file=sys.stderr)
    sys.exit(1)

stub = '''
@app.route("/api/vsp/run_fullscan_v1", methods=["POST"])
def vsp_run_fullscan_v1():
    """Stub API: nhận yêu cầu Run full scan từ UI.

    Payload dạng:
    {
      "source_root": "/path/or/null",
      "target_url": "https://app.or.null",
      "profile": "FULL_EXT",
      "mode": "EXT_ONLY | URL_ONLY | FULL_EXT"
    }
    """
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

    return jsonify({
        "ok": True,
        "source_root": source_root,
        "target_url": target_url,
        "profile": profile,
        "mode": mode
    })
'''

new_txt = txt.replace(marker, stub + '\n\n' + marker, 1)
path.write_text(new_txt, encoding="utf-8")
print("[OK] Đã chèn stub /api/vsp/run_fullscan_v1 trước main block.")
PY
