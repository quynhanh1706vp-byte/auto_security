#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="vsp_demo_app.py"
LOG_PREFIX="[PATCH_API_RUN_CLEAN]"

if [ ! -f "$APP" ]; then
  echo "$LOG_PREFIX [ERR] Không tìm thấy $ROOT/$APP"
  exit 1
fi

BACKUP="${APP}.bak_api_run_clean_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BACKUP"
echo "$LOG_PREFIX [BACKUP] $BACKUP"

python - << 'PY'
from pathlib import Path
import re
import textwrap

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

original = txt

# 1) Xóa mọi block có marker API VSP RUN FROM UI
pattern_marked = r'\n# === API VSP RUN FROM UI ===[\\s\\S]*?# === END API VSP RUN FROM UI ===\\n'
txt, n1 = re.subn(pattern_marked, "\n", txt)
print(f"[PATCH_API_RUN_CLEAN] Removed {n1} marked /api/vsp/run blocks.")

# 2) Xóa mọi block def api_vsp_run còn sót (không marker)
pattern_def = r'\n@app\\.route\\("/api/vsp/run"[\\s\\S]*?def\\s+api_vsp_run\\([^)]*\\):[\\s\\S]*?(?=\\n@app\\.route\\("|\\n# ===|\\Z)'
txt, n2 = re.subn(pattern_def, "\n", txt)
print(f"[PATCH_API_RUN_CLEAN] Removed {n2} unmarked /api/vsp/run blocks.")

if "/api/vsp/run" in txt:
    print("[PATCH_API_RUN_CLEAN][WARN] Sau khi cleanup vẫn còn chuỗi '/api/vsp/run' trong file, cần kiểm tra tay.")
else:
    print("[PATCH_API_RUN_CLEAN] Không còn route /api/vsp/run cũ nào.")

# 3) Append block mới duy nhất
new_block = textwrap.dedent("""
# === API VSP RUN FROM UI (CLEAN V1) ===
@app.route("/api/vsp/run", methods=["POST"])
def api_vsp_run():
    \"""
    Trigger scan từ UI:
    Body:
    {
      "mode": "local" | "ci",
      "profile": "FULL_EXT",
      "target_type": "path",
      "target": "/path/to/project"
    }
    \"""
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

    # Hiện tại chỉ hỗ trợ target_type=path
    if target_type != "path":
        return jsonify({
            "ok": False,
            "error": "Only target_type='path' is supported currently",
            "implemented": True
        }), 400

    # Nếu không truyền, default là project SECURITY-10-10-v4
    if not target:
        target = "/home/test/Data/SECURITY-10-10-v4"

    # Wrapper CI ở SECURITY_BUNDLE
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
# === END API VSP RUN FROM UI (CLEAN V1) ===
""").strip("\\n")

txt = txt.rstrip() + "\\n\\n" + new_block + "\\n"
app_path.write_text(txt, encoding="utf-8")

print("[PATCH_API_RUN_CLEAN] Appended clean /api/vsp/run block.")
PY

echo "$LOG_PREFIX [DONE]"
