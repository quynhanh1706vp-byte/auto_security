#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS (run p0_dashboard_luxe_v1.sh first)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
V="$(date +%s)"
echo "[INFO] TS=$TS V=$V"

echo "== backup luxe js =="
cp -f "$JS" "${JS}.bak_hidelegacy_${TS}"
echo "[BACKUP] ${JS}.bak_hidelegacy_${TS}"

echo "== patch luxe js: hide legacy #vsp5_root by default + toggle button =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

if "VSP_LUXE_HIDE_LEGACY_V1" not in s:
    # 1) add a helper to hide legacy root once mounted
    inject = r"""
  function hideLegacyByDefault(root){
    try{
      const legacy = document.querySelector('#vsp5_root');
      if (!legacy) return;
      // hide legacy UI (old dashboard) to keep luxe clean
      if (legacy.dataset && legacy.dataset.vspLuxeHidden === '1') return;
      legacy.style.display = 'none';
      if (legacy.dataset) legacy.dataset.vspLuxeHidden = '1';
    } catch {}
  }
"""
    # place after renderSkeleton
    s, n = re.subn(r'(function renderSkeleton\(root\)\{[\s\S]*?\}\n)\n',
                  r'\1\n' + inject + '\n', s, count=1)

    # 2) call hideLegacyByDefault after mountRoot
    s, n2 = re.subn(r'(const root = mountRoot\(\);\s*\n\s*renderSkeleton\(root\);\s*)',
                    r'\1\n      hideLegacyByDefault(root);\n', s, count=1)

    # 3) add toggle button in hero actions (best-effort)
    s = s.replace(
      '↗ Runs',
      '↗ Runs\n              </button>\n              <button class="vsp-btn" id="vspLuxeToggleLegacyBtn" title="Toggle legacy dashboard">▦ Legacy</button>\n              <button class="vsp-btn" id="vspLuxeOpenRunsBtn" title="Runs & Reports">\n                ↗ Runs'
    )

    # 4) wire toggle handler
    s = s.replace(
      "const runsBtn = el('#vspLuxeOpenRunsBtn', root);",
      "const tog = el('#vspLuxeToggleLegacyBtn', root);\n    if (tog) tog.addEventListener('click', () => {\n      try{\n        const legacy = document.querySelector('#vsp5_root');\n        if (!legacy) return;\n        legacy.style.display = (legacy.style.display === 'none') ? '' : 'none';\n      } catch {}\n    });\n\n    const runsBtn = el('#vspLuxeOpenRunsBtn', root);"
    )

    # mark
    s = "/* VSP_LUXE_HIDE_LEGACY_V1 */\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] luxe js patched (hide legacy + toggle)")
PY

echo "== find python file that serves /vsp5 =="
TARGET="$(python3 - <<'PY'
from pathlib import Path
import re

root = Path(".")
cands = []
for p in root.rglob("*.py"):
    if any(x in p.parts for x in ("bin","out","out_ci","node_modules",".venv","venv","__pycache__")):
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    # route decorators or add_url_rule
    if re.search(r'@[\w\.]*route\(\s*[\'"]/vsp5[\'"]', s) or re.search(r'add_url_rule\(\s*[\'"]/vsp5[\'"]', s):
        cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "$TARGET" ] || { echo "[ERR] cannot locate /vsp5 route in *.py"; exit 2; }
echo "[OK] /vsp5 route file: $TARGET"

cp -f "$TARGET" "${TARGET}.bak_vsp5luxe_${TS}"
echo "[BACKUP] ${TARGET}.bak_vsp5luxe_${TS}"

echo "== inject luxe script + host div into /vsp5 HTML in $TARGET =="
python3 - <<PY
from pathlib import Path
import re

p = Path("$TARGET")
s = p.read_text(encoding="utf-8", errors="replace")
v = "$V"

# 1) ensure host exists in /vsp5 html output: insert before vsp5_root if present
if 'id="vsp5_root"' in s and 'id="vsp_luxe_host"' not in s:
    s2, n = re.subn(r'(<div\\s+id="vsp5_root"[^>]*>\\s*</div>)',
                    r'<div id="vsp_luxe_host"></div>\\n  \\1', s, count=1)
    if n:
        s = s2

# 2) inject script after bundle tag if possible
if "vsp_dashboard_luxe_v1.js" not in s:
    # try after bundle commercial
    s2, n = re.subn(
        r'(<script\\s+src="\\/static\\/js\\/vsp_bundle_commercial_v2\\.js[^"]*"\\s*>\\s*<\\/script>)',
        r'\\1\\n<script src="/static/js/vsp_dashboard_luxe_v1.js?v=' + v + r'"></script>',
        s,
        count=1
    )
    if n == 0:
        # try before </body>
        s2, n = re.subn(r'(</body>)',
                        r'<script src="/static/js/vsp_dashboard_luxe_v1.js?v=' + v + r'"></script>\\n\\1',
                        s,
                        count=1)
    s = s2

p.write_text(s, encoding="utf-8")
print("[OK] injected luxe include + host (best effort)")
PY

echo "== py_compile key files =="
python3 -m py_compile "$TARGET"
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true
python3 -m py_compile vsp_demo_app.py 2>/dev/null || true
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 must include luxe script + host =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3 || { echo "[ERR] luxe still missing in /vsp5"; exit 2; }
curl -fsS "$BASE/vsp5" | grep -n 'id="vsp_luxe_host"' | head -n 3 || echo "[WARN] host not found (luxe can still mount elsewhere)"

echo "[DONE] Now hard refresh: Ctrl+Shift+R on /vsp5"
