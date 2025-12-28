from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

lines = txt.splitlines()
new_lines = []
skip = False
removed = 0

def is_start_of_run_block(line: str):
    return '@app.route("/api/vsp/run"' in line.replace(" ", "")

def is_def_api_vsp_run(line: str):
    return "def api_vsp_run" in line

# STEP 1: Remove any block containing /api/vsp/run
i = 0
n = len(lines)
while i < n:
    line = lines[i]

    if is_start_of_run_block(line):
        removed += 1
        skip = True

    if skip and is_def_api_vsp_run(line):
        skip = True

    if skip:
        i += 1
        # Stop skipping when next '@app.route(' appears AND it's not /api/vsp/run
        if i < n and "@app.route(" in lines[i] and "/api/vsp/run" not in lines[i]:
            skip = False
        continue

    new_lines.append(line)
    i += 1

print(f"[CLEAN_V2] Removed {removed} blocks of /api/vsp/run")

cleaned = "\n".join(new_lines).rstrip() + "\n\n"

# STEP 2: Append new clean block
new_block = '''
# === API VSP RUN FROM UI (CLEAN V2) ===
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
        return jsonify({"ok": False, "error": "Only target_type='path' is supported currently"}), 400

    if not target:
        target = "/home/test/Data/SECURITY-10-10-v4"

    wrapper = str(Path(__file__).resolve().parents[1] / "bin" / "vsp_ci_trigger_from_ui_v1.sh")

    try:
        proc = subprocess.Popen(
            [wrapper, profile, target, ci_mode],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        stdout, stderr = proc.communicate(timeout=5)
        req_id = (stdout or "").strip() or "UNKNOWN"

        if proc.returncode != 0:
            return jsonify({
                "ok": False,
                "implemented": True,
                "ci_triggered": False,
                "request_id": req_id,
                "stderr": (stderr or "")[-2000:]
            }), 500

        return jsonify({
            "ok": True,
            "implemented": True,
            "ci_triggered": True,
            "request_id": req_id,
            "profile": profile,
            "target": target,
            "ci_mode": ci_mode,
            "message": "Scan request accepted, running in background."
        })

    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

# === END API VSP RUN FROM UI (CLEAN V2) ===
'''

cleaned += new_block.strip() + "\n"

backup = app_path.with_suffix(".py.bak_clean_v2")
backup.write_text(txt, encoding="utf-8")
app_path.write_text(cleaned, encoding="utf-8")

print("[CLEAN_V2] Completed. Backup saved as", backup)
