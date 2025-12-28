#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need find; need grep; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

CSS_DIR="static/css"
OVR="${CSS_DIR}/vsp_theme_override_p1_v1.css"
mkdir -p "$CSS_DIR"

# 1) write override css (commercial contrast)
cp -f "$OVR" "${OVR}.bak_${TS}" 2>/dev/null || true
cat > "$OVR" <<'CSS'
/* VSP_THEME_OVERRIDE_P1_V1 */
/* Goal: higher contrast, readable text, nicer cards/buttons */
:root{
  --vsp-bg-0:#070b14;
  --vsp-bg-1:#0b1220;
  --vsp-card:rgba(255,255,255,0.06);
  --vsp-card-2:rgba(255,255,255,0.08);
  --vsp-border:rgba(255,255,255,0.10);
  --vsp-text:#eaf1ff;
  --vsp-text-2:#b8c6de;
  --vsp-muted:#7f8aa3;
  --vsp-link:#5db1ff;
  --vsp-link-2:#93d0ff;
  --vsp-danger:#ff5d6c;
  --vsp-warn:#ffb020;
  --vsp-ok:#41d67a;
}

html, body{ background: radial-gradient(1100px 700px at 25% 10%, rgba(50,120,255,0.18), transparent 55%),
                        radial-gradient(900px 600px at 80% 0%, rgba(255,90,120,0.10), transparent 50%),
                        linear-gradient(180deg, var(--vsp-bg-0), var(--vsp-bg-1)) !important;
            color: var(--vsp-text) !important; }

a{ color: var(--vsp-link) !important; }
a:hover{ color: var(--vsp-link-2) !important; text-decoration: underline; }

hr{ border-color: var(--vsp-border) !important; opacity: 1 !important; }

button, .btn, input[type="button"], input[type="submit"]{
  background: rgba(255,255,255,0.06) !important;
  border: 1px solid var(--vsp-border) !important;
  color: var(--vsp-text) !important;
  border-radius: 12px !important;
}
button:hover, .btn:hover{
  background: rgba(255,255,255,0.10) !important;
  border-color: rgba(130,190,255,0.35) !important;
}

input, textarea, select{
  background: rgba(255,255,255,0.05) !important;
  border: 1px solid var(--vsp-border) !important;
  color: var(--vsp-text) !important;
  border-radius: 10px !important;
}

.card, .panel, .box, .kpi, .kpi-card, .vsp-card, .vsp-panel,
div[class*="card"], div[class*="panel"], div[class*="kpi"]{
  background: var(--vsp-card) !important;
  border: 1px solid rgba(255,255,255,0.09) !important;
  box-shadow: 0 8px 30px rgba(0,0,0,0.35) !important;
  backdrop-filter: blur(6px);
}

small, .muted, .sub, .desc, .hint { color: var(--vsp-text-2) !important; }
code, pre { background: rgba(0,0,0,0.35) !important; border: 1px solid rgba(255,255,255,0.08) !important; }

.badge, .pill{
  background: rgba(255,255,255,0.08) !important;
  border: 1px solid rgba(255,255,255,0.10) !important;
  color: var(--vsp-text) !important;
  border-radius: 999px !important;
}

.vsp-error, .error, .alert-danger{
  background: rgba(255,93,108,0.12) !important;
  border: 1px solid rgba(255,93,108,0.35) !important;
  color: #ffd7db !important;
}
CSS
echo "[OK] wrote $OVR"

# 2) patch templates: inject override css link + fix bootjs src ONE query
python3 - <<PY
from pathlib import Path
import re, sys

ts = "${TS}"
ovr = f'/static/css/vsp_theme_override_p1_v1.css?v={ts}'
mark = "VSP_THEME_OVERRIDE_P1_V1"

tpl_root = Path("templates")
tps = sorted(tpl_root.glob("*.html"))
patched = []

for p in tps:
    s = p.read_text(encoding="utf-8", errors="replace")
    s0 = s

    # inject css link once before </head>
    if mark not in s:
        ins = f'\\n<!-- {mark} -->\\n<link rel="stylesheet" href="{ovr}">\\n'
        if "</head>" in s:
            s = s.replace("</head>", ins + "</head>", 1)

    # fix boot js src: force exactly .../vsp_p1_page_boot_v1.js?v=<TS>
    s = re.sub(r'(/static/js/vsp_p1_page_boot_v1\.js)\?v=[^"\\\']*', r'\\1?v='+ts, s)
    # in case there are broken double ?v=...?... patterns
    s = re.sub(r'(/static/js/vsp_p1_page_boot_v1\.js\?v=\d{8}_\d{6})(\\?v=[^"\\\']*)', r'\\1', s)

    if s != s0:
        p.write_text(s, encoding="utf-8")
        patched.append(p.name)

print("[OK] templates patched:", len(patched))
for x in patched[:30]:
    print(" -", x)
PY

# 3) restart UI (use your commercial starter if exists)
echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi

# 4) verify from server side (not browser cache)
echo "== verify vsp5 bootjs src =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 3 || true
echo "== verify override css link =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_theme_override_p1_v1.css" | head -n 3 || true
echo "== verify runs endpoint =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | sed -n '1,18p' || true

echo
echo "[NEXT] Mở Incognito http://127.0.0.1:8910/vsp5 (khuyến nghị) hoặc Ctrl+F5."
