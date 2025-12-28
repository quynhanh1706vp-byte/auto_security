#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, time

TS = time.strftime("%Y%m%d_%H%M%S")
tpl_dir = Path("templates")
if not tpl_dir.exists():
    raise SystemExit("[ERR] templates/ not found")

# Candidates that commonly render /vsp5
cands = [
  "vsp_5tabs_enterprise_v2.html",
  "vsp_5tabs_enterprise_v1.html",
  "vsp_dashboard_2025.html",
  "vsp5.html",
  "index.html",
]

inject_script = r'<script defer src="/static/js/vsp_dashboard_commercial_v1.js?v={{ asset_v }}"></script>'
inject_meta   = r'<meta name="vsp-page" content="dashboard"/>'

patched = 0
for name in cands:
    p = tpl_dir / name
    if not p.exists():
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    bak = p.with_name(p.name + f".bak_dashv1_force_{TS}")
    bak.write_text(s, encoding="utf-8")

    before = s

    # 1) remove GateStory script tags (any variant)
    s, n_rm = re.subn(
        r'\n?\s*<script[^>]+vsp_dashboard_gate_story_v1\.js[^>]*>\s*</script>\s*',
        '\n',
        s,
        flags=re.I
    )

    # 2) ensure meta marker in <head>
    if "name=\"vsp-page\"" not in s and "name='vsp-page'" not in s:
        if "</head>" in s:
            s = s.replace("</head>", "\n  "+inject_meta+"\n</head>", 1)
        else:
            s = inject_meta + "\n" + s

    # 3) ensure DashCommercialV1 script exists once (prefer before </body>)
    if "vsp_dashboard_commercial_v1.js" not in s:
        if "</body>" in s:
            s = s.replace("</body>", "\n  "+inject_script+"\n</body>", 1)
        else:
            s = s + "\n" + inject_script + "\n"

    # marker
    if "VSP_P1_DASHBOARD_FORCE_TEMPLATES_V2" not in s:
        if "</head>" in s:
            s = s.replace("</head>", "\n<!-- VSP_P1_DASHBOARD_FORCE_TEMPLATES_V2 -->\n</head>", 1)
        else:
            s = "<!-- VSP_P1_DASHBOARD_FORCE_TEMPLATES_V2 -->\n" + s

    if s != before:
        p.write_text(s, encoding="utf-8")
        patched += 1
        print(f"[OK] patched {p} (removed_gate_story={n_rm})")
    else:
        print(f"[OK] no change {p}")

print(f"[DONE] templates patched={patched}")
PY

echo
echo "[NEXT] Restart UI (gunicorn/systemd) then HARD refresh browser (Ctrl+Shift+R) on /vsp5."
