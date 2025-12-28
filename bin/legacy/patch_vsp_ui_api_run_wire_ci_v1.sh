#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"   # UI gateway app trên port 8910

LOG_PREFIX="[PATCH_API_RUN]"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $APP"
  exit 1
fi

BACKUP="${APP}.bak_api_run_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $BACKUP"

python - << 'PY'
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
app_path = root / "vsp_demo_app.py"

txt = app_path.read_text(encoding="utf-8")

pattern = r'''@app\.route\("/api/vsp/run"[\s\S]*?def\s+\w+\([^)]*\):[\s\S]*?(?=\n\n@app\.route|\n\n#\s*END_API_VSP_RUN|\Z)'''

new_block = r'''
@app.route("/api/vsp/run", methods=["POST"])
def api_vsp_run():
    """
    Trigger scan từ UI:
    Body:
    {
      "mode": "local" | "ci",
      "profile": "FULL_EXT",
      "target_type": "path",
      "target": "/path/to/project"
    }
    """
    import json
    import subprocess
    from pathlib import Path
    from flask import request, jsonify

    try:
        data = request.get_json(force=True, silent=True) or {}
    except Exception:
        data = {}

    mode = (data.get("mode") or "local").lower()
    profile = data.get("profile") or "FULL_EXT"
    target_type = data.get("target_type") or "path"
    target = data.get("target") or ""

    ci_mode = "LOCAL_UI"
    if mode in ("ci", "gitlab", "jenkins"):
        ci_mode = mode.upper() + "_UI"

    if target_type != "path":
        return jsonify({
            "ok": False,
            "error": "Only target_type='path' is supported currently",
            "implemented": True
        }), 400

    if not target:
        target = str(Path(__file__).resolve().parents[1])

    wrapper = str(Path(__file__).resolve().parents[1] / "bin" / "vsp_ci_trigger_from_ui_v1.sh")

    try:
        proc = subprocess.Popen(
            [wrapper, profile, target, ci_mode],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = proc.communicate(timeout=5)
        req_id = (stdout or "").strip()
        if not req_id:
            req_id = "UNKNOWN"

        if proc.returncode != 0:
            return jsonify({
                "ok": False,
                "implemented": True,
                "ci_triggered": False,
                "request_id": req_id,
                "error": "Wrapper exited with code {}".format(proc.returncode),
                "stderr": (stderr or "")[-4000:],
            }), 500

        return jsonify({
            "ok": True,
            "implemented": True,
            "ci_triggered": True,
            "request_id": req_id,
            "profile": profile,
            "target": target,
            "ci_mode": ci_mode,
            "message": "Scan request accepted, CI pipeline running in background."
        })

    except subprocess.TimeoutExpired:
        return jsonify({
            "ok": True,
            "implemented": True,
            "ci_triggered": True,
            "request_id": "TIMEOUT_SPAWN",
            "profile": profile,
            "target": target,
            "ci_mode": ci_mode,
            "message": "Scan request spawned (timeout on wrapper stdout).",
        })
    except FileNotFoundError:
        return jsonify({
            "ok": False,
            "implemented": False,
            "ci_triggered": False,
            "error": "Wrapper vsp_ci_trigger_from_ui_v1.sh not found.",
        }), 500
    except Exception as e:
        return jsonify({
            "ok": False,
            "implemented": False,
            "ci_triggered": False,
            "error": str(e),
        }), 500

# END_API_VSP_RUN
'''

m = re.search(pattern, txt, flags=re.MULTILINE)
if not m:
    print("[PATCH_API_RUN] [WARN] Không tìm thấy block cũ /api/vsp/run, sẽ append mới vào cuối file.")
    if "# END_API_VSP_RUN" in txt:
        txt = txt.replace("# END_API_VSP_RUN", new_block + "\n\n# END_API_VSP_RUN")
    else:
        txt = txt.rstrip() + "\n\n" + new_block + "\n"
else:
    txt = re.sub(pattern, new_block, txt, flags=re.MULTILINE)

app_path.write_text(txt, encoding="utf-8")
print("[PATCH_API_RUN] [OK] Đã patch /api/vsp/run để gọi CI wrapper.")
PY

echo "$LOG_PREFIX [DONE] Patched /api/vsp/run."
