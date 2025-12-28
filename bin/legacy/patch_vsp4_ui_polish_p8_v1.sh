#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_4tabs_commercial_v1.html"
[ -f "$TPL" ] || TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] cannot find vsp4 template"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_p8_ui_${TS}"
echo "[BACKUP] $TPL.bak_p8_ui_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("'"$TPL"'")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_UI_POLISH_P8_V1"
if MARK in s:
    print("[OK] already patched:", MARK); raise SystemExit(0)

# insert a safe CSS block before </head>
css = r"""
<!-- VSP_UI_POLISH_P8_V1 -->
<style>
  :root{
    --bg:#0b1020; --panel:#0f172a; --panel2:#111c33; --line:#1f2a44;
    --txt:#e5e7eb; --muted:#9ca3af; --good:#22c55e; --warn:#f59e0b; --bad:#ef4444;
    --accent:#60a5fa;
  }
  body{ background:var(--bg)!important; color:var(--txt)!important; }
  .vsp-wrap{ max-width:1400px; margin:0 auto; padding:18px 18px 28px; }
  .vsp-topbar{ display:flex; align-items:center; justify-content:space-between; gap:12px; margin-bottom:14px; }
  .vsp-brand{ font-weight:700; letter-spacing:.3px; font-size:18px; }
  .vsp-sub{ color:var(--muted); font-size:12px; }
  .vsp-tabs{ display:flex; gap:8px; flex-wrap:wrap; margin:12px 0 16px; }
  .vsp-tab{ cursor:pointer; padding:10px 12px; border:1px solid var(--line); background:var(--panel); border-radius:12px; color:var(--txt); }
  .vsp-tab.active{ border-color:rgba(96,165,250,.8); box-shadow:0 0 0 3px rgba(96,165,250,.12); }
  .vsp-card{ background:linear-gradient(180deg,var(--panel),var(--panel2)); border:1px solid var(--line); border-radius:16px; padding:14px; box-shadow:0 12px 30px rgba(0,0,0,.25); }
  .vsp-grid{ display:grid; grid-template-columns:repeat(12,1fr); gap:12px; }
  .col-3{ grid-column:span 3; } .col-4{ grid-column:span 4; } .col-6{ grid-column:span 6; } .col-12{ grid-column:span 12; }
  @media(max-width:1100px){ .col-3,.col-4,.col-6{ grid-column:span 12; } }
  .vsp-kpi{ display:flex; align-items:flex-start; justify-content:space-between; gap:10px; }
  .vsp-kpi .k{ font-size:12px; color:var(--muted); }
  .vsp-kpi .v{ font-size:24px; font-weight:800; line-height:1.1; margin-top:4px; }
  .pill{ display:inline-flex; align-items:center; gap:6px; padding:6px 10px; border-radius:999px; border:1px solid var(--line); background:rgba(255,255,255,.03); font-size:12px; color:var(--txt); }
  .dot{ width:8px; height:8px; border-radius:99px; background:var(--muted); display:inline-block; }
  .dot.good{ background:var(--good); } .dot.warn{ background:var(--warn);} .dot.bad{ background:var(--bad);}
  .btn{ cursor:pointer; padding:10px 12px; border-radius:12px; border:1px solid var(--line); background:rgba(255,255,255,.04); color:var(--txt); }
  .btn.primary{ border-color:rgba(96,165,250,.65); background:rgba(96,165,250,.14); }
  .btn:hover{ filter:brightness(1.08); }
  table{ width:100%; border-collapse:separate; border-spacing:0; }
  th,td{ padding:10px 10px; border-bottom:1px solid rgba(31,42,68,.65); font-size:12.5px; }
  th{ text-align:left; color:var(--muted); font-weight:600; }
  .muted{ color:var(--muted); }
  code,pre{ background:rgba(255,255,255,.04); border:1px solid var(--line); border-radius:10px; padding:2px 6px; }
</style>
"""

if "</head>" in s:
    s = s.replace("</head>", css + "\n</head>", 1)
else:
    s = css + "\n" + s

# wrap body content if not already
if 'class="vsp-wrap"' not in s:
    s = s.replace("<body", "<body><div class=\"vsp-wrap\">", 1)
    s = s.replace("</body>", "</div></body>", 1)

s = s.replace("VSP 4", "VSP Commercial", 1)
s = s.replace("class=\"tab", "class=\"vsp-tab tab", 1)  # harmless if not present

p.write_text(s, encoding="utf-8")
print("[OK] patched:", MARK, "=>", p)
PY

python3 -m py_compile vsp_demo_app.py >/dev/null 2>&1 || true
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh
echo "[NEXT] Ctrl+Shift+R http://127.0.0.1:8910/vsp4"
