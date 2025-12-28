#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
V="luxe_${TS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need curl; need grep; need head

CSS="static/css/vsp_cio_shell_v1.css"
[ -f "$CSS" ] || { echo "[ERR] missing $CSS (run cio shell first)"; exit 2; }

echo "== [1] Extend CIO CSS with dashboard luxe grid/shells =="
cp -f "$CSS" "${CSS}.bak_dashgrid_${TS}"
python3 - <<'PY'
from pathlib import Path
import time
p=Path("static/css/vsp_cio_shell_v1.css")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="/* === DASHBOARD LUXE GRID V1 === */"
if MARK in s:
    print("[OK] dash grid already present"); raise SystemExit(0)

add = f"""

{MARK}
.vsp-dash-grid {{
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: 14px;
  align-items: stretch;
}}

.vsp-dash-hero {{
  grid-column: 1 / -1;
  padding: 18px 18px 6px 18px;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(11,19,38,.62);
}}

.vsp-kpi-grid {{
  grid-column: 1 / -1;
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  gap: 12px;
}}

.vsp-kpi-card {{
  grid-column: span 2;
  min-height: 84px;
  padding: 12px 12px;
  border-radius: 16px;
  border: 1px solid var(--line);
  background: linear-gradient(180deg, rgba(12,22,44,.92), rgba(11,19,38,.92));
  box-shadow: 0 10px 26px rgba(0,0,0,.30);
}}
@media (max-width: 1280px) {{
  .vsp-kpi-card {{ grid-column: span 3; }}
}}
@media (max-width: 900px) {{
  .vsp-kpi-card {{ grid-column: span 6; }}
}}
@media (max-width: 520px) {{
  .vsp-kpi-card {{ grid-column: span 12; }}
}}

.vsp-kpi-title {{
  font-size: 11px;
  color: var(--muted);
  text-transform: uppercase;
  letter-spacing: .05em;
}}
.vsp-kpi-value {{
  font-size: 26px;
  font-weight: 800;
  color: var(--text);
  margin-top: 6px;
  line-height: 1.1;
}}
.vsp-kpi-sub {{
  font-size: 12px;
  color: rgba(148,163,184,.85);
  margin-top: 6px;
}}

.vsp-section {{
  grid-column: span 6;
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(11,19,38,.62);
  box-shadow: 0 10px 26px rgba(0,0,0,.26);
  overflow: hidden;
}}
.vsp-section--full {{ grid-column: 1 / -1; }}
@media (max-width: 900px) {{
  .vsp-section {{ grid-column: 1 / -1; }}
}}

.vsp-section-h {{
  padding: 12px 14px;
  border-bottom: 1px solid rgba(148,163,184,.14);
  display:flex;
  justify-content: space-between;
  align-items: center;
}}
.vsp-section-title {{
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: .06em;
  color: rgba(226,232,240,.9);
}}
.vsp-section-body {{
  padding: 12px 14px 14px 14px;
}}

.vsp-skeleton {{
  border-radius: 12px;
  border: 1px dashed rgba(148,163,184,.18);
  background: rgba(2,6,23,.25);
  color: rgba(148,163,184,.7);
  font-size: 12px;
  padding: 14px;
}}
"""
p.write_text(s.rstrip()+"\n"+add+"\n", encoding="utf-8")
print("[OK] extended CSS with dash grid v1")
PY

echo "== [2] Patch vsp_dashboard_luxe_v1.js to wrap KPI + sections (non-breaking) =="
JS="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_dashgrid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time
p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="/* VSP_DASH_LUXE_GRID_SHELLS_V1 */"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

inject = f"""
{MARK}
(function(){{
  function q(sel){{ return document.querySelector(sel); }}
  function wrapDash(){{
    // Only on /vsp5
    if (location.pathname !== "/vsp5") return;

    // prefer existing root(s)
    var root = q("#vsp-dashboard-main") || q("#vsp_tab_root") || document.body;
    if (!root) return;

    // create dashboard grid container once
    var grid = q(".vsp-dash-grid");
    if (!grid){{
      grid = document.createElement("div");
      grid.className = "vsp-dash-grid";
      // move visible dashboard content into grid
      var kids = Array.from(root.children);
      kids.forEach(function(el){{ grid.appendChild(el); }});
      root.appendChild(grid);
    }}

    // hero header placeholder (if no top header exists)
    if (!q(".vsp-dash-hero")){{
      var hero = document.createElement("div");
      hero.className="vsp-dash-hero";
      hero.innerHTML = '<div style="display:flex;justify-content:space-between;align-items:center;gap:12px">' +
        '<div><div style="font-size:14px;color:rgba(226,232,240,.95);font-weight:800">VSP 2025 — Security Overview</div>' +
        '<div style="font-size:12px;color:rgba(148,163,184,.85);margin-top:4px">Commercial CIO view • unified findings • 8-tool pipeline</div></div>' +
        '<div class="vsp-badge" style="font-family:var(--mono)">/vsp5</div>' +
      '</div>';
      grid.prepend(hero);
    }}

    // Try detect KPI container; if not, create shell that existing code can fill later
    var kpi = q("#vsp-kpi-root") || q(".vsp-kpi-grid");
    if (!kpi){{
      kpi = document.createElement("div");
      kpi.id="vsp-kpi-root";
      kpi.className="vsp-kpi-grid";
      // insert after hero
      var hero2=q(".vsp-dash-hero");
      hero2 && hero2.insertAdjacentElement("afterend", kpi);
    }} else {{
      kpi.classList.add("vsp-kpi-grid");
      kpi.id = kpi.id || "vsp-kpi-root";
    }}

    // Create 4 section shells (charts/tables placeholders) if missing
    function ensureSection(id,title,full){{
      var el=q("#"+id);
      if (el) return el;
      el=document.createElement("div");
      el.id=id;
      el.className="vsp-section"+(full?" vsp-section--full":"");
      el.innerHTML = '<div class="vsp-section-h"><div class="vsp-section-title">'+title+'</div></div>' +
                     '<div class="vsp-section-body"><div class="vsp-skeleton">Loading…</div></div>';
      grid.appendChild(el);
      return el;
    }}
    ensureSection("vsp-sec-chart-sev","Severity Distribution",false);
    ensureSection("vsp-sec-chart-trend","Trend (Findings over time)",false);
    ensureSection("vsp-sec-chart-tool","Critical/High by Tool",false);
    ensureSection("vsp-sec-chart-cwe","Top CWE Exposure",false);
    ensureSection("vsp-sec-table-top","Top Risk Findings",true);
    ensureSection("vsp-sec-table-bytool","By Tool Buckets",true);
  }}

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", wrapDash);
  }} else {{
    wrapDash();
  }}
}})();
"""
# append at end (safe)
p.write_text(s.rstrip()+"\n\n"+inject+"\n", encoding="utf-8")
print("[OK] appended dash grid shells v1")
PY

echo "== [3] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [4] Smoke: /vsp5 returns ok + contains grid class =="
curl -fsS --max-time 3 --range 0-220000 "$BASE/vsp5" | grep -n "vsp-dash-grid\|vsp_cio_shell_v1.css\|vsp_dashboard_luxe_v1.js" | head -n 20 || true

echo "[DONE] Ctrl+Shift+R on /vsp5."
