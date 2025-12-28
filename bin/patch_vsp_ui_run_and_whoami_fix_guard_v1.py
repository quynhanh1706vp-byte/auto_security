from pathlib import Path

f = Path("vsp_demo_app.py")
txt = f.read_text(encoding="utf-8")

backup = Path("vsp_demo_app.py.bak_run_whoami_fix_guard_v1")
backup.write_text(txt, encoding="utf-8")
print("[RUN_WHOAMI_FIX] Backup saved:", backup)

lines = txt.splitlines()
new_lines = []
skipping_run_block = False

for line in lines:
    # Bỏ toàn bộ block cũ của /api/vsp/run (nếu có)
    if '@app.route("/api/vsp/run"' in line:
        print("[RUN_WHOAMI_FIX] Removing old /api/vsp/run block...")
        skipping_run_block = True
        continue

    if skipping_run_block:
        # Dừng bỏ khi gặp route mới
        if line.strip().startswith("@app.route(") and '/api/vsp/run' not in line:
            skipping_run_block = False
            new_lines.append(line)
        else:
            continue
    else:
        new_lines.append(line)

txt_no_run = "\n".join(new_lines)

# Xoá mọi dòng whoami cũ (để tránh lộn xộn)
tmp_lines = []
for line in txt_no_run.splitlines():
    if '__vsp_ui_whoami' in line:
        continue
    tmp_lines.append(line)

txt_clean = "\n".join(tmp_lines)

# Block mới: WHOAMI + API RUN – đảm bảo top-level, đặt trước app.run
insert_block = '''
# === VSP UI WHOAMI DEBUG V2 + API RUN CI TRIGGER ===
@app.route("/__vsp_ui_whoami", methods=["GET"])
def vsp_ui_whoami():
    \"""
    Endpoint debug để kiểm tra app nào đang chạy trên gateway 8910.
    \"""
    from flask import jsonify
    import os
    return jsonify({
        "ok": True,
        "app": "vsp_demo_app",
        "cwd": os.getcwd(),
        "file": __file__,
    })

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
            "implemented": True,
            "ci_triggered": False,
            "error": "Only target_type='path' is supported currently"
        }), 400

    # Nếu không truyền, default là project SECURITY-10-10-v4
    if not target:
        target = "/home/test/Data/SECURITY-10-10-v4"

    wrapper = Path(__file__).resolve().parents[1] / "bin" / "vsp_ci_trigger_from_ui_v1.sh"

    if not wrapper.exists():
        return jsonify({
            "ok": False,
            "implemented": False,
            "ci_triggered": False,
            "error": f"Wrapper not found: {wrapper}"
        }), 500

    try:
        proc = subprocess.Popen(
            [str(wrapper), profile, target, ci_mode],
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
                "error": f"Wrapper exited with code {proc.returncode}",
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
            "message": "Scan request spawned (timeout on wrapper stdout)."
        })
    except Exception as e:
        return jsonify({
            "ok": False,
            "implemented": False,
            "ci_triggered": False,
            "error": str(e),
        }), 500
# === END VSP UI WHOAMI DEBUG V2 + API RUN CI TRIGGER ===

'''.strip() + "\n\n"

# Chèn block trước if __name__ == "__main__"
idx = txt_clean.find('if __name__ == "__main__"')
if idx == -1:
    idx = txt_clean.find("if __name__ == '__main__'")

if idx == -1:
    print("[RUN_WHOAMI_FIX][WARN] Không tìm thấy if __name__ == '__main__', sẽ append cuối file.")
    new_txt = txt_clean.rstrip() + "\n\n" + insert_block
else:
    print("[RUN_WHOAMI_FIX] Inserting block before if __name__ == '__main__'")
    new_txt = txt_clean[:idx] + insert_block + txt_clean[idx:]

f.write_text(new_txt, encoding="utf-8")
print("[RUN_WHOAMI_FIX] Done.")
