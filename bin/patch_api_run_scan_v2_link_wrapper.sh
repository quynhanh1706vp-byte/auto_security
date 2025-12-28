#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/app.py"

python3 - "$APP" <<'PY'
import sys, re, pathlib, textwrap

path = pathlib.Path(sys.argv[1])
data = path.read_text(encoding="utf-8")

pattern = r"@app.route\('/api/run_scan_v2'[\s\S]*?def\s+api_run_scan_v2\(\):[\s\S]*?(?=@app.route\(|$)"

new_block = '''
@app.route('/api/run_scan_v2', methods=['POST'])
def api_run_scan_v2():
    """Run scan từ UI, dùng wrapper bin/run_scan_and_refresh_ui.sh.

    Body JSON:
        { "src_folder": "/path/to/src" }
    """
    import subprocess, json, os

    payload = request.get_json(silent=True) or {}
    src = (payload.get('src_folder') or '').strip()
    if not src:
        return jsonify({"ok": False, "error": "Missing src_folder"}), 400

    root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    script = os.path.join(root, 'bin', 'run_scan_and_refresh_ui.sh')

    if not os.path.exists(script):
        return jsonify({"ok": False, "error": f"Wrapper script not found: {script}"}), 500

    try:
        proc = subprocess.run(
            [script, src],
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=True,
        )
        output = proc.stdout
        return jsonify({"ok": True, "src": src, "log": output})
    except subprocess.CalledProcessError as e:
        return jsonify({
            "ok": False,
            "src": src,
            "error": "run_scan_and_refresh_ui.sh failed",
            "log": e.stdout or str(e),
        }), 500
'''
m = re.search(pattern, data)
if not m:
    print("[WARN] Không tìm thấy block /api/run_scan_v2 để thay thế", file=sys.stderr)
else:
    data = data[:m.start()] + textwrap.dedent(new_block).lstrip('\n') + "\n\n" + data[m.end():]
    path.write_text(data, encoding="utf-8")
    print("[OK] Đã thay block /api/run_scan_v2 dùng wrapper run_scan_and_refresh_ui.sh")
PY
