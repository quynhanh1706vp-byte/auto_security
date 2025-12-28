#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_bundle_syntax_v13_${TS}"
echo "[BACKUP] ${F}.bak_bundle_syntax_v13_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

SAFE_LINE = (
  "bundle_tag = f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\\n"
  "<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={v}\"></script>\\n"
  "<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>\\n"
  "<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={v}\"></script>'"
)

def is_scriptish(ln: str) -> bool:
    t = ln.strip()
    return (
        "<script" in t or "</script>" in t or
        "vsp_bundle_commercial_v2.js" in t or
        "vsp_dashboard_" in t or
        "gate_story" in t or
        "containers_fix" in t or
        "luxe" in t
    )

out = []
i = 0
patched = 0

while i < len(lines):
    ln = lines[i]
    if re.search(r'^\s*bundle_tag\s*=\s*f', ln):
        indent = re.match(r'^(\s*)', ln).group(1)

        # kill current line + following "script-ish" or empty/comment lines (max 120 lines)
        j = i + 1
        while j < len(lines) and (j - i) < 120:
            if is_scriptish(lines[j]) or not lines[j].strip() or lines[j].lstrip().startswith("#"):
                j += 1
                continue
            # stop when we hit something that looks like real code
            break

        out.append(indent + SAFE_LINE + "\n")
        patched += 1
        i = j
        continue

    out.append(ln)
    i += 1

if patched == 0:
    raise SystemExit("[ERR] cannot find bundle_tag assignment to patch")

p.write_text("".join(out), encoding="utf-8")
print("[OK] patched bundle_tag blocks:", patched)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] fixed SyntaxError + restarted"
