#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need sed

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fix_fstring_v4_${TS}"
echo "[BACKUP] ${F}.bak_fix_fstring_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

# We will rewrite the assignment to bundle_tag into a safe single-line f-string.
# Target: a line starting with optional spaces then: bundle_tag = f'<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>
# and it's broken across lines.
out = []
i = 0
fixed = 0

while i < len(lines):
    line = lines[i]
    if re.search(r'^\s*bundle_tag\s*=\s*f[\'"]<script\s+src="/static/js/vsp_bundle_commercial_v2\.js\?v=\{v\}"></script>', line):
        # If this line is already complete (contains closing quote), keep it.
        if re.search(r'[\'"]\s*$', line.strip()):
            out.append(line)
            i += 1
            continue

        # Otherwise consume subsequent lines until we hit a line that ends the string or a reasonable bound
        j = i + 1
        while j < len(lines) and j < i + 12:
            if re.search(r'[\'"]\s*$', lines[j].strip()):
                j += 1
                break
            j += 1

        indent = re.match(r'^(\s*)', line).group(1)
        out.append(indent + 'bundle_tag = f\'<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>\'\n')
        fixed += 1
        i = j
        continue

    out.append(line)
    i += 1

if fixed == 0:
    # fallback: find any broken bundle_tag line that mentions vsp_bundle_commercial_v2.js and "bundle_tag = f"
    out2 = []
    fixed2 = 0
    for ln in out:
        if "bundle_tag" in ln and "vsp_bundle_commercial_v2.js" in ln and "bundle_tag = f" in ln:
            # nuke it to a safe version (single line)
            indent = re.match(r'^(\s*)', ln).group(1)
            out2.append(indent + 'bundle_tag = f\'<script src="/static/js/vsp_bundle_commercial_v2.js?v={v}"></script>\'\n')
            fixed2 += 1
        else:
            out2.append(ln)
    out = out2
    fixed = fixed2

p.write_text("".join(out), encoding="utf-8")
print("[OK] fixed bundle_tag f-string occurrences:", fixed)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] fixed f-string + restarted"
