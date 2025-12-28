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

echo "== find file that contains VSP5 HTML marker =="
TARGET="$(python3 - <<'PY'
from pathlib import Path

root = Path(".")
MARKERS = [
  "VSP_P1_VSP5_SWITCH_TO_DASHCOMMERCIAL_V1_FIX_V1",
  "<title>VSP5</title>",
  "vsp5nav",
  'id="vsp5_root"',
  "vsp_dashboard_gate_story_v1.js",
]
EXCL_DIRS = {"bin","out","out_ci","node_modules",".venv","venv","__pycache__"}

cands = []
for p in root.rglob("*"):
    if not p.is_file(): 
        continue
    if p.suffix not in (".py",".html"):
        continue
    if any(part in EXCL_DIRS for part in p.parts):
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    score = sum(1 for m in MARKERS if m in s)
    if score >= 2 and "vsp_bundle_commercial_v2.js" in s:
        cands.append((score, str(p)))

cands.sort(reverse=True)
print(cands[0][1] if cands else "")
PY
)"
[ -n "$TARGET" ] || { echo "[ERR] cannot find VSP5 HTML builder by marker"; exit 2; }
echo "[OK] TARGET=$TARGET"

cp -f "$TARGET" "${TARGET}.bak_vsp5luxe_${TS}"
echo "[BACKUP] ${TARGET}.bak_vsp5luxe_${TS}"

echo "== inject host div + luxe script into TARGET =="
python3 - <<PY
from pathlib import Path
import re

p = Path("$TARGET")
s = p.read_text(encoding="utf-8", errors="replace")
v = "$V"

# 1) ensure host exists (before vsp5_root)
if 'id="vsp5_root"' in s and 'id="vsp_luxe_host"' not in s:
    s2, n = re.subn(r'(<div\\s+id="vsp5_root"[^>]*>\\s*</div>)',
                    r'<div id="vsp_luxe_host"></div>\\n  \\1', s, count=1)
    if n:
        s = s2

# 2) inject luxe script after bundle tag (best effort)
if "vsp_dashboard_luxe_v1.js" not in s:
    # Try: after bundle commercial script tag
    s2, n = re.subn(
        r'(<script\\s+src="\\/static\\/js\\/vsp_bundle_commercial_v2\\.js[^"]*"\\s*>\\s*<\\/script>)',
        r'\\1\\n',
        s,
        count=1
    )
    if n == 0:
        # fallback: before <script defer src="/static/js/vsp_dash_only_v1.js?v=20251222_072320"></script>
</body>
        s2, n = re.subn(r'(</body>)',
                        r'\\n\\1',
                        s,
                        count=1)
    s = s2

p.write_text(s, encoding="utf-8")
print("[OK] injected luxe include + host into", p)
PY

echo "== py_compile if TARGET is .py =="
if [[ "$TARGET" == *.py ]]; then
  python3 -m py_compile "$TARGET"
fi
echo "[OK] compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 must include luxe script =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3 || { echo "[ERR] luxe still missing in /vsp5"; exit 2; }

echo "[DONE] Hard refresh /vsp5: Ctrl+Shift+R"
