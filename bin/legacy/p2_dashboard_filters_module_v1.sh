#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_p2_dashboard_filters_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p static/js templates || true

cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JSFILE'
/* vsp_p2_dashboard_filters_v1 */
(function(){
  function ready(fn){ if(document.readyState!=="loading") fn(); else document.addEventListener("DOMContentLoaded", fn); }
  function qs(sel,root){ return (root||document).querySelector(sel); }
  function qsa(sel,root){ return Array.from((root||document).querySelectorAll(sel)); }

  function mount(){
    // Find a reasonable anchor on dashboard
    var main = document.getElementById("vsp-dashboard-main") || qs("[data-vsp-dashboard]") || document.body;
    if(!main || document.getElementById("vsp-p2-filters")) return;

    var bar = document.createElement("div");
    bar.id="vsp-p2-filters";
    bar.style.cssText="display:flex;gap:10px;align-items:center;padding:10px 12px;margin:10px 0;border:1px solid #333;border-radius:12px;background:#0f1218;color:#ddd;font:12px/1.2 monospace;flex-wrap:wrap";
    bar.innerHTML = ''
      + '<span style="opacity:.9">FILTER</span>'
      + '<select id="vsp-f-sev" style="background:#111;border:1px solid #333;color:#ddd;border-radius:10px;padding:6px 10px">'
      + '<option value="">severity=ALL</option><option>CRITICAL</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option><option>INFO</option><option>TRACE</option></select>'
      + '<input id="vsp-f-q" placeholder="search title/file/tool/cwe" style="min-width:260px;background:#111;border:1px solid #333;color:#ddd;border-radius:10px;padding:6px 10px" />'
      + '<button id="vsp-f-apply" style="background:#111;border:1px solid #333;color:#bfffe8;border-radius:10px;padding:6px 10px;cursor:pointer">Apply → Data Source</button>'
      + '<button id="vsp-f-clear" style="background:#111;border:1px solid #333;color:#ffe6bf;border-radius:10px;padding:6px 10px;cursor:pointer">Clear</button>';

    // Insert near top of main
    main.prepend(bar);

    function navToDataSource(){
      var sev = (qs("#vsp-f-sev")||{}).value || "";
      var q = (qs("#vsp-f-q")||{}).value || "";
      var url = new URL("/data_source", window.location.origin);
      if(sev) url.searchParams.set("severity", sev);
      if(q) url.searchParams.set("q", q);
      window.location.href = url.toString();
    }

    qs("#vsp-f-apply").addEventListener("click", navToDataSource);
    qs("#vsp-f-clear").addEventListener("click", function(){
      qs("#vsp-f-sev").value="";
      qs("#vsp-f-q").value="";
    });

    // Click-through: any element containing severity text becomes a shortcut
    ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(function(S){
      qsa("*").slice(0,800).forEach(function(node){
        if(!node || node.children && node.children.length>8) return;
        var t=(node.textContent||"").trim();
        if(t===S || t.startsWith(S+" ")) {
          node.style.cursor="pointer";
          node.addEventListener("click", function(e){
            var url = new URL("/data_source", window.location.origin);
            url.searchParams.set("severity", S);
            window.location.href=url.toString();
          });
        }
      });
    });
  }

  ready(mount);
})();
JSFILE

echo "[OK] wrote $JS"

# patch template: find dashboard html
python3 - <<'PY'
from pathlib import Path
import re, sys

cand=[]
for p in Path("templates").rglob("*.html"):
    s=p.read_text(encoding="utf-8", errors="replace")
    if "vsp-dashboard-main" in s or "/vsp5" in s or "vsp5" in p.name:
        cand.append(p)

if not cand:
    print("[ERR] cannot locate dashboard template in templates/*.html")
    sys.exit(2)

t=cand[0]
s=t.read_text(encoding="utf-8", errors="replace")
if "vsp_p2_dashboard_filters_v1.js" in s:
    print("[OK] template already includes P2 module:", t)
    sys.exit(0)

ins = '\n<script src="/static/js/vsp_p2_dashboard_filters_v1.js?v=1"></script>\n'
if "</body>" in s:
    s = s.replace("</body>", ins + "</body>", 1)
else:
    s = s + ins
t_bak = t.with_suffix(".html.bak_p2filters")
t_bak.write_text(t.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
t.write_text(s, encoding="utf-8")
print("[OK] patched template:", t, " backup:", t_bak)
PY

sudo systemctl restart "${VSP_UI_SVC:-vsp-ui-8910.service}"
echo "[OK] restarted"
echo "[OK] open /vsp5 then you should see FILTER bar"
