#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="app.py"

python3 - <<'PY'
from pathlib import Path
import textwrap

path = Path("app.py")
data = path.read_text(encoding="utf-8")

marker = '@app.route("/api/run_scan_v2"'
idx = data.find(marker)
if idx == -1:
    print("[ERR] Không thấy route /api/run_scan_v2 trong app.py")
    raise SystemExit(0)

end = data.find('@app.route("', idx+1)
if end == -1:
    end = data.find('if __name__ == "__main__"', idx+1)

new_block = textwrap.dedent('''
@app.route("/api/run_scan_v2", methods=["POST"])
def api_run_scan_v2():
    """Trigger full scan từ UI – đọc SRC folder & Target URL từ form."""
    import subprocess
    from pathlib import Path
    import os

    ROOT = Path(__file__).resolve().parent.parent
    payload = request.get_json(silent=True) or {}

    src = (payload.get("src") or "").strip()
    target_url = (payload.get("target_url") or "").strip()

    if not src:
        src = os.environ.get("SB_DEFAULT_SRC", "/home/test/Data/Khach")

    print(f"[API][RUN_SCAN_V2] src={src!r}, target_url={target_url!r}", flush=True)

    cmd = f'cd "{ROOT}" && bin/run_scan_and_refresh_ui.sh "{src}"'
    completed = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True)
    rc = completed.returncode
    out_tail = completed.stdout[-8000:]
    err_tail = completed.stderr[-8000:]
    return jsonify({
        "ok": rc == 0,
        "rc": rc,
        "cmd": cmd,
        "stdout_tail": out_tail,
        "stderr_tail": err_tail,
    })
''')

old_block = data[idx:end]
data = data[:idx] + new_block + data[end:]
path.write_text(data, encoding="utf-8")
print("[OK] Đã patch route /api/run_scan_v2 để dùng SRC từ UI.")
PY
