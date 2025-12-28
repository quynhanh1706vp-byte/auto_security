#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_runstatus_notfound_json200_${TS}"
echo "[BACKUP] $PYF.bak_runstatus_notfound_json200_${TS}"

python3 - << 'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

m = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_status_v1(req_id):")

start = m.start()
# end = next top-level def
m2 = re.search(r"^\s*def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = (m.end() + m2.start()) if m2 else len(txt)

block = txt[start:end]

# Nếu đã patch rồi thì skip
marker = "VSP_RUN_STATUS_NOTFOUND_JSON200_V1"
if marker in block:
    print("[INFO] already patched; skip")
else:
    # 1) Thay abort(404) / abort(404, ...) trong block
    repl = (
        'return jsonify({'
        '"ok": False, "req_id": req_id, "status": "NOT_FOUND", "final": True, '
        '"error": "REQ_ID_NOT_FOUND"'
        '}), 200  # ' + marker
    )
    block2 = re.sub(r"\babort\s*\(\s*404\s*(?:,[^\)]*)?\)\s*", repl, block)

    # 2) Thay return ... , 404 (các dạng phổ biến)
    block2 = re.sub(
        r"return\s+jsonify\s*\(\s*\{[^\}]*\}\s*\)\s*,\s*404",
        repl,
        block2,
        flags=re.S
    )
    block2 = re.sub(
        r"return\s+\([^\)]*\)\s*,\s*404",
        repl,
        block2,
        flags=re.S
    )

    # Nếu không thay được gì (không có abort/return 404), vẫn thêm “fallback notfound” ngay cuối handler (trước khi end)
    if block2 == block:
        # chèn fallback trước dòng cuối cùng của function (naive: trước end of block)
        # tìm vị trí cuối cùng có indent 4 spaces trở lên (trong function)
        lines = block.splitlines(True)
        # thêm vào cuối function
        lines.append(
            "\n    # " + marker + "\n"
            "    # Fallback: nếu đến đây mà chưa return thì coi như NOT_FOUND\n"
            "    return jsonify({\"ok\": False, \"req_id\": req_id, \"status\": \"NOT_FOUND\", \"final\": True, \"error\": \"REQ_ID_NOT_FOUND\"}), 200\n"
        )
        block2 = "".join(lines)
        print("[WARN] no abort/404 found; appended fallback return at end of handler")
    else:
        print("[OK] replaced abort/return 404 -> JSON 200 NOT_FOUND")

    txt = txt[:start] + block2 + txt[end:]
    p.write_text(txt, encoding="utf-8")

import py_compile
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY
