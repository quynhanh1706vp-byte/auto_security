#!/usr/bin/env bash
set -euo pipefail

APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
BK="${APP}.bak_hotfix_run_status_500_v1_$(date +%Y%m%d_%H%M%S)"
cp "$APP" "$BK"
echo "[BACKUP] $BK"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Ensure essential imports exist
def ensure_import(line):
    nonlocal_txt = None
    return line

# Add: import traceback, from flask import jsonify (if not present)
if "import traceback" not in txt:
    txt = "import traceback\n" + txt

# ensure jsonify imported
if re.search(r"from\s+flask\s+import\s+.*\bjsonify\b", txt) is None:
    m = re.search(r"from\s+flask\s+import\s+(.*)$", txt, flags=re.M)
    if m:
        # extend existing flask import line
        orig = m.group(0)
        if "jsonify" not in orig:
            new = orig.rstrip() + ", jsonify"
            txt = txt.replace(orig, new, 1)
    else:
        # prepend a minimal flask import
        txt = "from flask import jsonify\n" + txt

# ensure Path and re exist
if "from pathlib import Path" not in txt:
    txt = "from pathlib import Path\n" + txt
if re.search(r"^import\s+re\s*$", txt, flags=re.M) is None and "import re" not in txt:
    txt = "import re\n" + txt

# 2) Wrap api_vsp_run_status with try/except returning JSON error
# Find function def api_vsp_run_status(req_id):
m = re.search(r"@app\.route\(\"/api/vsp/run_status/<req_id>\"[^\n]*\)\ndef\s+api_vsp_run_status\s*\(req_id\)\s*:\n", txt)
if not m:
    raise SystemExit("[ERR] Không tìm thấy def api_vsp_run_status(req_id)")

start = m.end()
# Grab function body by indentation
lines = txt[start:].splitlines(True)
body = []
indent = None
for ln in lines:
    if ln.strip() == "":
        body.append(ln); continue
    if indent is None:
        indent = len(ln) - len(ln.lstrip(" "))
    # stop when indentation goes back to 0 (new top-level def/route)
    if (len(ln) - len(ln.lstrip(" "))) < (indent or 0) and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@app.route")):
        break
    body.append(ln)

old_body = "".join(body)
if "traceback.format_exc" in old_body:
    print("[INFO] run_status already wrapped, skip wrap.")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

# Build new wrapped body
# Remove leading indent from old body, then re-indent inside try:
def strip_indent(s, n):
    out=[]
    for ln in s.splitlines(True):
        if ln.strip()=="":
            out.append(ln); continue
        out.append(ln[n:] if ln.startswith(" "*n) else ln)
    return "".join(out)

core = strip_indent(old_body, indent or 0).rstrip("\n")
wrapped = ""
wrapped += "    try:\n"
for ln in core.splitlines():
    wrapped += "        " + ln + "\n"
wrapped += "    except Exception as e:\n"
wrapped += "        return jsonify({\n"
wrapped += "            \"ok\": False,\n"
wrapped += "            \"error\": str(e),\n"
wrapped += "            \"trace\": traceback.format_exc()\n"
wrapped += "        }), 500\n"

# Replace old body with wrapped body (keep original indentation already 4 spaces)
new_txt = txt[:start] + wrapped + txt[start+len(old_body):]
p.write_text(new_txt, encoding="utf-8")
print("[OK] Wrapped api_vsp_run_status with try/except and ensured imports.")
PY

echo "[DONE] Hotfix applied. Restart 8910 then re-test run_status."
echo "Restart:"
echo "  pkill -f vsp_demo_app.py || true"
echo "  nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &"
