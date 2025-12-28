#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
VER="cio_${TS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need head

CSS="static/css/vsp_cio_shell_v1.css"
JS="static/js/vsp_cio_shell_apply_v1.js"

[ -f "$CSS" ] || { echo "[ERR] missing $CSS"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

echo "== [0] Backup CSS =="
cp -f "$CSS" "${CSS}.bak_polishv2_${TS}"
echo "[BACKUP] ${CSS}.bak_polishv2_${TS}"

echo "== [1] Append CIO polish v2 (CSS-only) =="
python3 - <<'PY'
from pathlib import Path
css = Path("static/css/vsp_cio_shell_v1.css")
s = css.read_text(encoding="utf-8", errors="replace")
marker="VSP_CIO_POLISH_V2_CSS_ONLY"
if marker in s:
    print("[SKIP] already applied", marker)
else:
    add = r"""
/* VSP_CIO_POLISH_V2_CSS_ONLY */
/* Goals:
   - consistent spacing, cards, tables, buttons, inputs across all tabs
   - dashboard: KPI grid, chart shells, section headers look enterprise
   - keep JS untouched (CSS-only)
*/
:root{
  --vsp-bg0:#0b1220; --vsp-bg1:#0f172a; --vsp-bg2:#111c33;
  --vsp-card:#0f1a2f; --vsp-card2:#0b1528;
  --vsp-bd:rgba(148,163,184,.18);
  --vsp-t0:#e5e7eb; --vsp-t1:#cbd5e1; --vsp-t2:#94a3b8;
  --vsp-ac:#60a5fa; --vsp-ac2:#22c55e; --vsp-warn:#f59e0b; --vsp-err:#ef4444;
  --vsp-shadow: 0 12px 30px rgba(0,0,0,.35);
  --vsp-radius: 16px;
  --vsp-radius-sm: 12px;
  --vsp-pad: 14px;
}

body.vsp-cio-shell{
  background: radial-gradient(1200px 800px at 20% 10%, rgba(96,165,250,.12), transparent 55%),
              radial-gradient(900px 600px at 90% 25%, rgba(34,197,94,.10), transparent 55%),
              linear-gradient(180deg, var(--vsp-bg0), var(--vsp-bg1) 40%, #0a1020);
  color: var(--vsp-t0);
}

.vsp-cio-shell a{ color: var(--vsp-ac); }
.vsp-cio-shell a:hover{ filter: brightness(1.08); }

.vsp-cio-shell .vsp-container,
.vsp-cio-shell #vsp_tab_root{
  max-width: 1360px;
  margin: 0 auto;
}

.vsp-cio-shell .vsp-card,
.vsp-cio-shell .card,
.vsp-cio-shell .panel,
.vsp-cio-shell .box{
  background: linear-gradient(180deg, rgba(255,255,255,.04), rgba(255,255,255,.02));
  border: 1px solid var(--vsp-bd);
  border-radius: var(--vsp-radius);
  box-shadow: var(--vsp-shadow);
}

.vsp-cio-shell .vsp-card{ padding: var(--vsp-pad); }

.vsp-cio-shell h1,.vsp-cio-shell h2,.vsp-cio-shell h3{
  letter-spacing: .2px;
}
.vsp-cio-shell .vsp-section-title{
  display:flex; align-items:center; gap:10px;
  font-weight: 700; font-size: 14px;
  color: var(--vsp-t0);
  margin: 6px 0 10px;
}
.vsp-cio-shell .vsp-section-title:before{
  content:"";
  width:10px; height:10px; border-radius: 999px;
  background: rgba(96,165,250,.9);
  box-shadow: 0 0 0 4px rgba(96,165,250,.15);
}

.vsp-cio-shell button, .vsp-cio-shell .btn, .vsp-cio-shell .button{
  border-radius: 12px;
  border: 1px solid var(--vsp-bd);
  background: rgba(255,255,255,.05);
  color: var(--vsp-t0);
  padding: 8px 12px;
  cursor: pointer;
}
.vsp-cio-shell button:hover, .vsp-cio-shell .btn:hover, .vsp-cio-shell .button:hover{
  filter: brightness(1.08);
}
.vsp-cio-shell .btn-primary{
  background: linear-gradient(180deg, rgba(96,165,250,.85), rgba(96,165,250,.55));
  border-color: rgba(96,165,250,.45);
  color:#06101f;
  font-weight: 700;
}
.vsp-cio-shell .btn-danger{
  background: linear-gradient(180deg, rgba(239,68,68,.85), rgba(239,68,68,.55));
  border-color: rgba(239,68,68,.45);
  color:#1a0a0a;
  font-weight: 700;
}

.vsp-cio-shell input, .vsp-cio-shell select, .vsp-cio-shell textarea{
  border-radius: 12px;
  border: 1px solid var(--vsp-bd);
  background: rgba(2,6,23,.55);
  color: var(--vsp-t0);
  padding: 8px 10px;
  outline: none;
}
.vsp-cio-shell input:focus, .vsp-cio-shell select:focus, .vsp-cio-shell textarea:focus{
  border-color: rgba(96,165,250,.55);
  box-shadow: 0 0 0 4px rgba(96,165,250,.12);
}

.vsp-cio-shell table{
  width: 100%;
  border-collapse: separate;
  border-spacing: 0;
}
.vsp-cio-shell th, .vsp-cio-shell td{
  border-bottom: 1px solid var(--vsp-bd);
  padding: 10px 10px;
  vertical-align: top;
}
.vsp-cio-shell thead th{
  position: sticky; top: 0;
  background: rgba(2,6,23,.65);
  backdrop-filter: blur(6px);
  z-index: 2;
  color: var(--vsp-t1);
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: .7px;
}
.vsp-cio-shell tbody tr:hover{
  background: rgba(96,165,250,.06);
}

/* Dashboard KPI grid helpers (works even if markup varies) */
.vsp-cio-shell .vsp-kpi-grid,
.vsp-cio-shell .kpi-grid{
  display:grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 1200px){
  .vsp-cio-shell .vsp-kpi-grid, .vsp-cio-shell .kpi-grid{ grid-template-columns: repeat(3, minmax(0,1fr)); }
}
@media (max-width: 720px){
  .vsp-cio-shell .vsp-kpi-grid, .vsp-cio-shell .kpi-grid{ grid-template-columns: repeat(2, minmax(0,1fr)); }
}

.vsp-cio-shell .vsp-kpi,
.vsp-cio-shell .kpi-card{
  background: linear-gradient(180deg, rgba(255,255,255,.045), rgba(255,255,255,.02));
  border: 1px solid var(--vsp-bd);
  border-radius: var(--vsp-radius-sm);
  padding: 12px;
  box-shadow: var(--vsp-shadow);
}
.vsp-cio-shell .vsp-kpi .label,
.vsp-cio-shell .kpi-label{
  color: var(--vsp-t2);
  font-size: 12px;
}
.vsp-cio-shell .vsp-kpi .value,
.vsp-cio-shell .kpi-value{
  font-size: 22px;
  font-weight: 800;
  letter-spacing: .2px;
}

/* Scrollbar subtle */
.vsp-cio-shell ::-webkit-scrollbar{ height: 10px; width: 10px; }
.vsp-cio-shell ::-webkit-scrollbar-thumb{ background: rgba(148,163,184,.22); border-radius: 999px; }
.vsp-cio-shell ::-webkit-scrollbar-thumb:hover{ background: rgba(148,163,184,.32); }
"""
    css.write_text(s.rstrip()+"\n"+add+"\n", encoding="utf-8")
    print("[OK] appended", marker)
PY

echo "== [2] Bump ver in templates (CSS+JS querystring) =="
python3 - <<PY
from pathlib import Path
import re, sys

ver="${VER}"
root=Path("templates")
files=list(root.rglob("*.html"))
patched=0

for f in files:
    s=f.read_text(encoding="utf-8", errors="replace")
    s2=s
    s2=re.sub(r'(vsp_cio_shell_v1\.css\?v=)cio_[0-9_]+', r'\\1'+ver, s2)
    s2=re.sub(r'(vsp_cio_shell_apply_v1\.js\?v=)cio_[0-9_]+', r'\\1'+ver, s2)
    if s2!=s:
        f.write_text(s2, encoding="utf-8")
        patched += 1

print("[OK] templates_bumped=", patched, "ver=", ver)
PY

echo "== [3] Restart service best-effort =="
if command -v systemctl >/dev/null 2>&1; then
  (sudo systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted $SVC") || echo "[WARN] restart failed or svc not found: $SVC"
fi

echo "== [4] Smoke: check /vsp5 includes new ver =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --max-time 3 --range 0-120000 "$BASE/vsp5" | grep -n "vsp_cio_shell_v1.css\\|vsp_cio_shell_apply_v1.js" | head -n 6 || true

echo "[DONE] Ctrl+Shift+R /vsp5 + open all tabs."
