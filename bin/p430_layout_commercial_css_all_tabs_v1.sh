#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need node; need date

CSS="static/css/vsp_layout_commercial_v1.css"
mkdir -p static/css

if [ -f "$CSS" ]; then
  cp -f "$CSS" "${CSS}.bak_${TS}"
fi

cat > "$CSS" <<'CSS'
/* VSP_LAYOUT_COMMERCIAL_V1
   Safe styling layer: improves layout consistency across 5 tabs without touching JS behavior.
*/
:root{
  --vsp-bg: #0b1220;
  --vsp-panel: rgba(255,255,255,.04);
  --vsp-panel2: rgba(255,255,255,.06);
  --vsp-border: rgba(255,255,255,.08);
  --vsp-text: rgba(255,255,255,.88);
  --vsp-muted: rgba(255,255,255,.65);
  --vsp-radius: 14px;
  --vsp-gap: 14px;
  --vsp-gap2: 18px;
  --vsp-shadow: 0 8px 26px rgba(0,0,0,.35);
  --vsp-font: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
}

html, body{ font-family: var(--vsp-font); color: var(--vsp-text); }
body{ background: var(--vsp-bg); }

a{ color: inherit; text-decoration: none; }
a:hover{ text-decoration: underline; }

.vsp-shell, .container, .main, #app, #root, #vsp_app{
  max-width: 1280px;
  margin: 0 auto;
  padding: 16px;
}

.vsp-page-title, h1{
  font-size: 18px;
  letter-spacing: .2px;
  margin: 6px 0 14px 0;
}

.vsp-card, .card, .panel{
  background: var(--vsp-panel);
  border: 1px solid var(--vsp-border);
  border-radius: var(--vsp-radius);
  box-shadow: var(--vsp-shadow);
}

.vsp-card{ padding: 14px; }
.vsp-card + .vsp-card{ margin-top: var(--vsp-gap); }

.vsp-row{ display:flex; gap: var(--vsp-gap); flex-wrap: wrap; }
.vsp-col{ flex: 1 1 320px; min-width: 320px; }

.vsp-actions{ display:flex; gap: 10px; align-items:center; flex-wrap: wrap; }
button, .btn{
  background: var(--vsp-panel2);
  border: 1px solid var(--vsp-border);
  color: var(--vsp-text);
  border-radius: 12px;
  padding: 8px 12px;
  cursor: pointer;
}
button:hover, .btn:hover{ filter: brightness(1.12); }

input, select, textarea{
  background: rgba(255,255,255,.03);
  border: 1px solid var(--vsp-border);
  color: var(--vsp-text);
  border-radius: 12px;
  padding: 8px 10px;
  outline: none;
}
input::placeholder, textarea::placeholder{ color: rgba(255,255,255,.35); }

table{ width: 100%; border-collapse: collapse; }
th, td{ padding: 10px 10px; border-bottom: 1px solid rgba(255,255,255,.06); }
th{ text-align: left; color: var(--vsp-muted); font-weight: 600; font-size: 12px; }
td{ font-size: 13px; }
tr:hover td{ background: rgba(255,255,255,.02); }

.vsp-badge{
  display:inline-flex; align-items:center; gap:6px;
  padding: 4px 10px; border-radius: 999px;
  border: 1px solid var(--vsp-border);
  background: rgba(255,255,255,.03);
  font-size: 12px; color: var(--vsp-muted);
}

.vsp-empty, .empty-state{
  padding: 18px;
  border: 1px dashed rgba(255,255,255,.16);
  border-radius: var(--vsp-radius);
  color: var(--vsp-muted);
  background: rgba(255,255,255,.02);
}

.vsp-footer{
  margin-top: 18px;
  color: rgba(255,255,255,.45);
  font-size: 12px;
}
CSS

node --check "$CSS" >/dev/null 2>&1 || true

# Inject CSS link into templates (once)
python3 - <<'PY'
from pathlib import Path
import datetime, re

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
css_href = "/static/css/vsp_layout_commercial_v1.css"

tpls = list(Path("templates").glob("**/*.html"))
patched = 0
for t in tpls:
    s = t.read_text(encoding="utf-8", errors="replace")
    if css_href in s:
        continue
    # place before </head> if exists
    if "</head>" in s:
        s2 = s.replace("</head>", f'  <link rel="stylesheet" href="{css_href}">\n</head>', 1)
        bak = t.with_suffix(t.suffix + f".bak_p430_{ts}")
        bak.write_text(s, encoding="utf-8")
        t.write_text(s2, encoding="utf-8")
        patched += 1

print("patched_templates=", patched)
PY

echo "[OK] P430 css added: $CSS"
