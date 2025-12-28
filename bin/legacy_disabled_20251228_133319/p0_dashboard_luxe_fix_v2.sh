#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS (run p0_dashboard_luxe_v1.sh first)"; exit 2; }
cp -f "$JS" "${JS}.bak_fix_${TS}"
echo "[BACKUP] ${JS}.bak_fix_${TS}"

echo "== patch luxe JS to mount into #vsp_luxe_host first =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# ensure anchor list contains '#vsp_luxe_host' at the top
s2, n = re.subn(
    r'const anchors = \[\s*([\s\S]*?)\];',
    lambda m: (
        'const anchors = [\n'
        "      '#vsp_luxe_host',\n" +
        re.sub(r"^\s*'#vsp_luxe_host',\s*\n?", "", m.group(1), flags=re.M) +
        '\n    ];'
    ),
    s,
    count=1
)

if n == 0:
    print("[WARN] cannot find anchors array; leaving JS unchanged")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] updated anchors to prefer #vsp_luxe_host")
PY

if [ "$node_ok" -eq 1 ]; then
  echo "== node --check $JS =="
  node --check "$JS" >/dev/null && echo "[OK] node syntax OK"
fi

echo "== patch /vsp5 html generator (python files) =="
python3 - <<'PY'
from pathlib import Path
import re, time

TS = time.strftime("%Y%m%d_%H%M%S")
targets = [Path("vsp_demo_app.py"), Path("wsgi_vsp_ui_gateway.py")]
for p in targets:
    if not p.exists():
        print("[WARN] missing", p)
        continue

    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_dashluxe_fix_{TS}")
    bak.write_text(s, encoding="utf-8")

    changed = False

    # 1) add host div before vsp5_root if vsp5_root exists but host missing
    if 'id="vsp5_root"' in s and 'id="vsp_luxe_host"' not in s:
        s2, n = re.subn(r'(<div\s+id="vsp5_root"\s*>\s*</div>)',
                        r'<div id="vsp_luxe_host"></div>\n  \1', s, count=1)
        if n:
            s = s2
            changed = True
            print("[OK]", p.name, "inserted #vsp_luxe_host before #vsp5_root")

    # 2) inject luxe script after bundle include (works for inline HTML string)
    if "vsp_dashboard_luxe_v1.js" not in s:
        # find the bundle script line and append luxe script under it
        s2, n = re.subn(
            r'(<script\s+src="\/static\/js\/vsp_bundle_commercial_v2\.js\?v=[^"]+"\s*>\s*<\/script>)',
            r'\1\n<script src="/static/js/vsp_dashboard_luxe_v1.js?v=%s"></script>' % TS,
            s,
            count=1
        )
        if n == 0:
            # also support "?js?v=..." or "?v=..." variants
            s2, n = re.subn(
                r'(<script\s+src="\/static\/js\/vsp_bundle_commercial_v2\.js[^"]*"\s*>\s*<\/script>)',
                r'\1\n<script src="/static/js/vsp_dashboard_luxe_v1.js?v=%s"></script>' % TS,
                s,
                count=1
            )
        if n:
            s = s2
            changed = True
            print("[OK]", p.name, "injected luxe script after bundle")
        else:
            print("[WARN]", p.name, "cannot find bundle script tag to inject (maybe different HTML builder)")

    if changed:
        p.write_text(s, encoding="utf-8")
    else:
        print("[SKIP]", p.name, "no change needed / already patched")

print("[DONE] python patch finished")
PY

echo "== py_compile =="
python3 -m py_compile vsp_demo_app.py
python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: /vsp5 must include luxe script + host div =="
curl -fsS "$BASE/vsp5" | grep -n "vsp_dashboard_luxe_v1.js" | head -n 3 || { echo "[ERR] luxe script still missing in /vsp5"; exit 2; }
curl -fsS "$BASE/vsp5" | grep -n 'id="vsp_luxe_host"' | head -n 3 || { echo "[WARN] host div not found (still may work)"; true; }

echo "[DONE] Reload /vsp5 with hard refresh (Ctrl+Shift+R)."
