from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8")

lines = txt.splitlines()
new_lines = []
skip = False
removed = 0

def is_start_of_dast_block(line: str):
    return '@app.route("/api/vsp/dast/scan"' in line.replace(" ", "")

def is_def_api_vsp_dast_scan(line: str):
    return "def api_vsp_dast_scan" in line

i = 0
n = len(lines)
while i < n:
    line = lines[i]

    if is_start_of_dast_block(line):
        removed += 1
        skip = True

    if skip and is_def_api_vsp_dast_scan(line):
        skip = True

    if skip:
        i += 1
        # dừng skip khi gặp route khác
        if i < n and "@app.route(" in lines[i] and "/api/vsp/dast/scan" not in lines[i]:
            skip = False
        continue

    new_lines.append(line)
    i += 1

print(f"[DAST_CLEAN] Removed {removed} blocks of /api/vsp/dast/scan")

cleaned = "\n".join(new_lines).rstrip() + "\n\n"

new_block = '''
# === API VSP DAST SCAN (CLEAN V1) ===
@app.route("/api/vsp/dast/scan", methods=["POST"])
def api_vsp_dast_scan():
    """
    Stub DAST từ UI:
    Body:
    {
      "url": "https://example.com"
    }
    Hiện tại chỉ ghi lịch sử planned, chưa gọi Nessus/ZAP thật.
    """
    from flask import request, jsonify
    from pathlib import Path
    import json
    import datetime

    data = request.get_json(silent=True) or {}
    url = data.get("url") or ""

    root = Path(__file__).resolve().parents[1]
    hist_path = root / "out" / "dast_history.json"
    hist_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        history = json.loads(hist_path.read_text(encoding="utf-8"))
        if not isinstance(history, list):
            history = []
    except Exception:
        history = []

    entry = {
        "url": url,
        "engine": "DAST_STUB_V1",
        "status": "PLANNED",
        "created_at": datetime.datetime.utcnow().isoformat() + "Z",
    }
    history.append(entry)
    hist_path.write_text(json.dumps(history, indent=2), encoding="utf-8")

    return jsonify({
        "ok": True,
        "implemented": False,
        "engine": "DAST_STUB_V1",
        "url": url,
        "status": "PLANNED"
    })
# === END API VSP DAST SCAN (CLEAN V1) ===
'''

cleaned += new_block.strip() + "\n"

backup = app_path.with_suffix(".py.bak_dast_clean_v1")
backup.write_text(txt, encoding="utf-8")
app_path.write_text(cleaned, encoding="utf-8")

print("[DAST_CLEAN] Completed. Backup saved as", backup)
