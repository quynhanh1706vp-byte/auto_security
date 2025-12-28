from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

marker = "# === END VSP RULE OVERRIDES SAVE API (CLEAN V1) ==="
if marker not in txt:
    # fallback: append cuối file
    marker = None

whoami_block = r'''
# === VSP UI WHOAMI DEBUG V1 ===
@app.route("/__vsp_ui_whoami", methods=["GET"])
def vsp_ui_whoami():
    """
    Endpoint debug để kiểm tra app nào đang chạy trên gateway 8910.
    """
    from flask import jsonify
    import os
    return jsonify({
        "ok": True,
        "app": "vsp_demo_app",
        "cwd": os.getcwd(),
        "file": __file__,
    })
# === END VSP UI WHOAMI DEBUG V1 ===
'''.strip() + "\n"

if marker and marker in txt:
    new_txt = txt.replace(marker, marker + "\n\n" + whoami_block)
else:
    new_txt = txt.rstrip() + "\n\n" + whoami_block

backup = app_path.with_suffix(".py.bak_whoami_v1")
backup.write_text(txt, encoding="utf-8")
app_path.write_text(new_txt, encoding="utf-8")

print("[WHOAMI_PATCH] Backup saved as", backup)
print("[WHOAMI_PATCH] Patched vsp_demo_app.py with /__vsp_ui_whoami")
