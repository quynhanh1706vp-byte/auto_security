#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

CSS="static/css/vsp_polish_p1_v1.css"
TPL="templates/vsp_dashboard_2025.html"

mkdir -p static/css

TS="$(date +%Y%m%d_%H%M%S)"
[ -f "$CSS" ] && cp -f "$CSS" "$CSS.bak_${TS}" && echo "[BACKUP] $CSS.bak_${TS}"
cp -f "$TPL" "$TPL.bak_polish_${TS}" && echo "[BACKUP] $TPL.bak_polish_${TS}"

cat > "$CSS" <<'CSS'
/* VSP_POLISH_P1_V1: safe cosmetics only */

:root{
  --vsp-border: rgba(255,255,255,.10);
  --vsp-bg: rgba(255,255,255,.03);
}

.vsp-card, .dashboard-card{
  border: 1px solid var(--vsp-border) !important;
  background: var(--vsp-bg) !important;
  border-radius: 14px !important;
}

.vsp-bdg, .badge, .pill{
  border: 1px solid rgba(255,255,255,.14) !important;
  font-weight: 900 !important;
  letter-spacing: .2px !important;
}

/* soften heavy glow/blur without breaking theme */
body::before, .bg-glow, .glow, .blur{
  filter: none !important;
  opacity: .85 !important;
}

/* tighten buttons in actions columns */
button, .btn, a.btn{
  border-radius: 999px !important;
}

/* empty data state */
.no-data, .empty, [data-empty]{
  opacity: .78 !important;
}

/* runs table readability */
table{
  border-collapse: separate !important;
  border-spacing: 0 10px !important;
}
th{ opacity:.78 !important; font-weight:800 !important; }
td{ opacity:.92 !important; }
CSS

python3 - <<'PY'
from pathlib import Path
import re, datetime
tpl = Path("templates/vsp_dashboard_2025.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

# inject <link> once
if "vsp_polish_p1_v1.css" not in t:
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    link = f'<link rel="stylesheet" href="/static/css/vsp_polish_p1_v1.css?v={stamp}"/>'
    if "</head>" in t:
        t = re.sub(r"</head>", link + "\n</head>", t, count=1, flags=re.I)
    else:
        t = link + "\n" + t
    tpl.write_text(t, encoding="utf-8")
    print("[OK] injected polish css link")
else:
    print("[OK] polish css already linked")
PY

echo "[OK] wrote $CSS"
echo "[NEXT] restart UI + hard refresh"
