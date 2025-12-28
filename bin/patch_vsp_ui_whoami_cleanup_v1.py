import re
from pathlib import Path

f = Path("vsp_demo_app.py")
txt = f.read_text(encoding="utf-8")

# Backup
backup = Path("vsp_demo_app.py.bak_whoami_cleanup_v1")
backup.write_text(txt, encoding="utf-8")
print("[WHOAMI_CLEAN] Backup saved:", backup)

pattern = re.compile(
    r"@app\.route\(\"/__vsp_ui_whoami\"[\s\S]*?return jsonify\([\s\S]*?\}\),?\s*\)",
    re.MULTILINE
)

blocks = pattern.findall(txt)
print("[WHOAMI_CLEAN] Found blocks:", len(blocks))

if len(blocks) <= 1:
    print("[WHOAMI_CLEAN] Nothing to clean.")
    exit(0)

# Keep ONLY the first block
first = blocks[0]
cleaned = txt

# Remove all except the first occurrence
for b in blocks[1:]:
    cleaned = cleaned.replace(b, "")

f.write_text(cleaned, encoding="utf-8")
print("[WHOAMI_CLEAN] Cleaned duplicate whoami blocks.")
