from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

lines = txt.splitlines()
new_lines = []
skip = False
removed = 0

def is_start_of_rule_save_block(line: str):
    return '@app.route("/api/vsp/rule_overrides_save_v1"' in line.replace(" ", "")

def is_def_rule_save(line: str):
    return "def vsp_rule_overrides_save_v1" in line

i = 0
n = len(lines)
while i < n:
    line = lines[i]

    if is_start_of_rule_save_block(line):
        removed += 1
        skip = True

    if skip and is_def_rule_save(line):
        skip = True

    if skip:
        i += 1
        # dừng skip khi gặp route khác
        if i < n and "@app.route(" in lines[i] and "/api/vsp/rule_overrides_save_v1" not in lines[i]:
            skip = False
        continue

    new_lines.append(line)
    i += 1

print(f"[RULE_SAVE_CLEAN] Removed {removed} blocks of /api/vsp/rule_overrides_save_v1")

cleaned = "\n".join(new_lines).rstrip() + "\n\n"

new_block = '''
# === VSP RULE OVERRIDES SAVE API (CLEAN V1) ===
@app.route("/api/vsp/rule_overrides_save_v1", methods=["POST"])
def vsp_rule_overrides_save_v1():
    """
    Nhận JSON root object (đúng schema rule_overrides_ui_v1)
    Ghi xuống out/vsp_rule_overrides_v1.json (backup bản cũ nếu có).
    """
    from flask import request, jsonify
    from pathlib import Path
    import json

    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return jsonify({"ok": False, "error": "Root JSON phải là object."}), 400

    root = Path(__file__).resolve().parents[1]
    overrides_path = root / "out" / "vsp_rule_overrides_v1.json"
    overrides_path.parent.mkdir(parents=True, exist_ok=True)

    # Backup cũ
    if overrides_path.exists():
        backup = overrides_path.with_suffix(".json.bak_ui_save")
        try:
            overrides_path.replace(backup)
        except Exception:
            pass

    overrides_path.write_text(
        json.dumps(data, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )

    return jsonify({"ok": True, "path": str(overrides_path)})
# === END VSP RULE OVERRIDES SAVE API (CLEAN V1) ===
'''

cleaned += new_block.strip() + "\n"

backup = app_path.with_suffix(".py.bak_rule_save_clean_v1")
backup.write_text(txt, encoding="utf-8")
app_path.write_text(cleaned, encoding="utf-8")

print("[RULE_SAVE_CLEAN] Completed. Backup saved as", backup)
