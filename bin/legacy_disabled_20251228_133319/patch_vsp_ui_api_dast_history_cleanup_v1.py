from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

lines = txt.splitlines()
new_lines = []
skip = False
removed = 0

def is_start_of_hist_block(line: str):
    return '@app.route("/api/vsp/dast/history"' in line.replace(" ", "")

def is_def_api_vsp_dast_history(line: str):
    return "def api_vsp_dast_history" in line

i = 0
n = len(lines)
while i < n:
    line = lines[i]

    if is_start_of_hist_block(line):
        removed += 1
        skip = True

    if skip and is_def_api_vsp_dast_history(line):
        skip = True

    if skip:
        i += 1
        # Dừng skip khi gặp route khác
        if i < n and "@app.route(" in lines[i] and "/api/vsp/dast/history" not in lines[i]:
            skip = False
        continue

    new_lines.append(line)
    i += 1

print(f"[DAST_HIST_CLEAN] Removed {removed} blocks of /api/vsp/dast/history")

cleaned = "\n".join(new_lines).rstrip() + "\n\n"

new_block = '''
# === API VSP DAST HISTORY (CLEAN V1) ===
@app.route("/api/vsp/dast/history", methods=["GET"])
def api_vsp_dast_history():
    """
    Trả lại lịch sử DAST stub (dast_history.json)
    """
    from flask import jsonify
    from pathlib import Path
    import json

    root = Path(__file__).resolve().parents[1]
    hist_path = root / "out" / "dast_history.json"

    try:
        data = json.loads(hist_path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            data = []
    except Exception:
        data = []

    return jsonify({
        "ok": True,
        "items": data,
    })
# === END API VSP DAST HISTORY (CLEAN V1) ===
'''

cleaned += new_block.strip() + "\n"

backup = app_path.with_suffix(".py.bak_dast_hist_clean_v1")
backup.write_text(txt, encoding="utf-8")
app_path.write_text(cleaned, encoding="utf-8")

print("[DAST_HIST_CLEAN] Completed. Backup saved as", backup)
