#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_bundle_blockkill_${TS}"
echo "[BACKUP] ${F}.bak_bundle_blockkill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

SAFE_LINE = (
  r"bundle_tag = f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\n"
  r"<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={v}\"></script>\n"
  r"<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>'"
)

def is_scriptish(ln: str) -> bool:
    t = ln.strip()
    return (
        "<script" in t or "</script>" in t or
        "vsp_bundle_commercial_v2.js" in t or
        "vsp_dashboard_" in t or
        "vsp_dashboard_containers_fix_v1.js" in t
    )

out = []
i = 0
patched = 0
while i < len(lines):
    ln = lines[i]
    if re.search(r'^\s*bundle_tag\s*=\s*.*vsp_bundle_commercial_v2\.js', ln):
        indent = re.match(r'^(\s*)', ln).group(1)

        # kill the whole broken block: current line + following scriptish lines until it looks like code resumes
        j = i + 1
        # If the first line already ends with quote, it's a single-line assignment; still replace it.
        # Otherwise, consume up to 80 lines, but stop early when non-scriptish and looks like code.
        while j < len(lines) and (j - i) < 80:
            if is_scriptish(lines[j]):
                j += 1
                continue
            # stop if we hit something that looks like code (non-empty, not comment, not string chunk)
            if lines[j].strip() and not lines[j].lstrip().startswith("#"):
                break
            j += 1

        out.append(indent + SAFE_LINE + "\n")
        patched += 1
        i = j
        continue

    out.append(ln)
    i += 1

if patched == 0:
    raise SystemExit("[ERR] cannot find any bundle_tag line referencing vsp_bundle_commercial_v2.js")

p.write_text("".join(out), encoding="utf-8")
print("[OK] patched bundle_tag blocks:", patched)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 includes both scripts =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_containers_fix_v1.js" | head -n 2
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 2
echo "[DONE] Ctrl+Shift+R on /vsp5"
