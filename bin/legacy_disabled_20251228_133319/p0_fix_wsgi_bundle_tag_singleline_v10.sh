#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_bundle_tag_v10_${TS}"
echo "[BACKUP] ${F}.bak_bundle_tag_v10_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

SAFE_LINE = r"bundle_tag = f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\n<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={v}\"></script>'"

# 1) Fix broken triple-quote block: bundle_tag = f""" ... """ plus any garbage on same line (like \n)
pat1 = re.compile(r'^(\s*)bundle_tag\s*=\s*f""".*?"""[^\n]*\n', re.M | re.S)
s, n1 = pat1.subn(lambda m: m.group(1) + SAFE_LINE + "\n", s)

# 2) Fix any single/double-quote bundle_tag line that references bundle script (even if partially broken)
pat2 = re.compile(r'^(\s*)bundle_tag\s*=\s*f[\'"].*vsp_bundle_commercial_v2\.js.*\n', re.M)
s, n2 = pat2.subn(lambda m: m.group(1) + SAFE_LINE + "\n", s)

if (n1 + n2) == 0:
    raise SystemExit("[ERR] cannot find bundle_tag assignment to patch")

p.write_text(s, encoding="utf-8")
print(f"[OK] patched bundle_tag lines: {n1+n2} (triple={n1}, single={n2})")
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] fixed bundle_tag single-line + restarted"
