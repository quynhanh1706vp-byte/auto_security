#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pdf_nf501_${TS}"
echo "[BACKUP] $F.bak_pdf_nf501_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PDF_NF_TO_501_V1" in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# Replace error payload style seen in your response:
# {"error":"PDF_NOT_FOUND","http_code":404,...}
s2 = s

# 1) replace PDF_NOT_FOUND string
s2 = s2.replace('"PDF_NOT_FOUND"', '"pdf_not_enabled"')

# 2) replace http_code 404 -> 501 where tied to pdf_not_enabled/PDF_NOT_FOUND
s2 = re.sub(r'("http_code"\s*:\s*)404\b', r'\g<1>501', s2)

# 3) if there is an explicit resp.status_code = 404 in export path, flip it too
# (safe-ish heuristic: only in lines that mention PDF_NOT_FOUND or pdf_not_enabled nearby)
lines = s2.splitlines(True)
out=[]
for i,line in enumerate(lines):
    if "status_code" in line and "404" in line:
        window = "".join(lines[max(0,i-3):min(len(lines),i+4)])
        if ("PDF_NOT_FOUND" in window) or ("pdf_not_enabled" in window) or ("fmt" in window and "pdf" in window):
            line = line.replace("404", "501")
    out.append(line)
s2 = "".join(out)

# 4) add marker
s2 += "\n# === VSP_PDF_NF_TO_501_V1 ===\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched PDF_NOT_FOUND -> 501 pdf_not_enabled")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 gunicorn"
