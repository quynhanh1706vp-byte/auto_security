#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="api/vsp_run_export_api_v3.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_indent_${TS}"
echo "[BACKUP] $F.bak_fix_indent_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("api/vsp_run_export_api_v3.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

marker = "# [COMMERCIAL] on-demand export"
i_marker = None
for i, ln in enumerate(lines):
    if marker in ln:
        i_marker = i
        break
if i_marker is None:
    raise SystemExit("[ERR] cannot find on-demand marker")

# find the first "except" after marker
i_exc = None
exc_indent = ""
for j in range(i_marker, min(len(lines), i_marker + 250)):
    ln = lines[j]
    # detect "except" line (any Exception variant)
    stripped = ln.lstrip(" ")
    if stripped.startswith("except ") or stripped.startswith("except\t"):
        i_exc = j
        exc_indent = ln[:len(ln) - len(stripped)]
        break

if i_exc is None:
    raise SystemExit("[ERR] cannot find except after on-demand marker")

# consume old except body: from except line to next line that is NOT:
# - blank
# - more-indented than exc_indent
k = i_exc + 1
def is_more_indented(line: str) -> bool:
    if line.strip() == "":
        return True
    # treat tabs as 4 spaces conservatively
    s = line.replace("\t", "    ")
    ind = len(s) - len(s.lstrip(" "))
    base = len(exc_indent.replace("\t","    "))
    return ind > base

while k < len(lines) and is_more_indented(lines[k]):
    k += 1

# build new except block with correct indentation
base = exc_indent
body = base + "    "
new_block = []
# keep original except header but normalize to "except Exception as e:"
new_block.append(base + "except Exception as e:\n")
new_block.append(body + "# do not silently fallback to stub (pdf_not_enabled)\n")
new_block.append(body + "detail = f\"{type(e).__name__}:{e}\"\n")
new_block.append(body + "resp = jsonify({\"ok\": False, \"error\": \"export_ondemand_exception\", \"detail\": detail})\n")
new_block.append(body + "resp.headers[\"X-VSP-EXPORT-AVAILABLE\"] = \"0\"\n")
new_block.append(body + "resp.headers[\"X-VSP-EXPORT-MODE\"] = \"ONDEMAND_V2_EXCEPTION\"\n")
new_block.append(body + "return resp, 500\n")

# replace
lines = lines[:i_exc] + new_block + lines[k:]

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] fixed except indentation at lines {i_exc+1}-{k} (replaced with {len(new_block)} lines)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"
