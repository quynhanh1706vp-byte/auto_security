#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need grep

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

# 1) CSS override
CSS_DIR="static/css"
OVR="${CSS_DIR}/vsp_theme_override_p1_v2.css"
mkdir -p "$CSS_DIR"
cp -f "$OVR" "${OVR}.bak_${TS}" 2>/dev/null || true
cat > "$OVR" <<'CSS'
/* VSP_THEME_OVERRIDE_P1_V2 */
:root{
  --vsp-bg0:#070a12; --vsp-bg1:#0b1020;
  --vsp-card:rgba(14,21,40,.88);
  --vsp-text:#e8eefc; --vsp-muted:#a8b3d6;
  --vsp-line:rgba(255,255,255,.08);
  --vsp-accent:#6ea8ff;
}
html,body{
  background: radial-gradient(1200px 700px at 30% 10%, rgba(110,168,255,.12), transparent 60%),
              radial-gradient(900px 600px at 70% 15%, rgba(138,125,255,.10), transparent 55%),
              linear-gradient(180deg, var(--vsp-bg1), var(--vsp-bg0));
  color: var(--vsp-text);
}
a{ color: var(--vsp-accent) !important; }
a:hover{ text-decoration: underline; }
.card,.panel,.box,.vsp-card,.vsp-panel{
  background: linear-gradient(180deg, var(--vsp-card), rgba(9,14,30,.88)) !important;
  border: 1px solid var(--vsp-line) !important;
  box-shadow: 0 10px 24px rgba(0,0,0,.35) !important;
}
button,.btn{
  border: 1px solid rgba(255,255,255,.10) !important;
  background: rgba(255,255,255,.06) !important;
  color: var(--vsp-text) !important;
}
button:hover,.btn:hover{ background: rgba(255,255,255,.10) !important; }
input,textarea,select{
  background: rgba(255,255,255,.04) !important;
  border: 1px solid rgba(255,255,255,.12) !important;
  color: var(--vsp-text) !important;
}
.vsp-degraded-banner{
  margin: 10px 0 0 0;
  padding: 10px 12px;
  border: 1px solid rgba(255,204,102,.35);
  background: rgba(255,204,102,.10);
  color: var(--vsp-text);
  border-radius: 10px;
  font-size: 13px;
}
CSS
echo "[OK] wrote $OVR"

# 2) Patch templates: inject CSS link + force bootjs src to exactly ?v=TS (match until ")
python3 - <<PY
from pathlib import Path
import re

ts="${TS}"
css_href=f'/static/css/vsp_theme_override_p1_v2.css?v={ts}'
tpls=[
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_data_source_v1.html",
  "templates/vsp_rule_overrides_v1.html",
]
changed=[]
for t in tpls:
  p=Path(t)
  if not p.exists(): 
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s0=s

  # normalize boot js src => /static/js/vsp_p1_page_boot_v1.js?v=TS
  s=re.sub(r'(/static/js/vsp_p1_page_boot_v1\\.js)(\\?v=[^"]*)?', r'\\1?v='+ts, s)
  # remove accidental double ?v=
  s=re.sub(r'(/static/js/vsp_p1_page_boot_v1\\.js\\?v=[^"]*)\\?v=[^"]*', r'\\1', s)

  if "vsp_theme_override_p1_v2.css" not in s and "</head>" in s:
    s=s.replace("</head>", f'\\n<link rel="stylesheet" href="{css_href}">\\n</head>', 1)

  if s!=s0:
    p.write_text(s, encoding="utf-8")
    changed.append(p.name)

print("[OK] templates patched:", len(changed))
for x in changed: print(" -", x)
PY

# 3) Patch boot JS: XHR runs loader (bypass fetch wrappers) + degrade banner
cp -f "$JS" "${JS}.bak_finish_${TS}"
echo "[BACKUP] ${JS}.bak_finish_${TS}"

python3 - <<'PY'
from pathlib import Path
import time
p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_XHR_RUNS_FALLBACK_V3"
if MARK in s:
  print("[OK] marker already present:", MARK)
  raise SystemExit(0)

inject = f"""
/* {MARK} {time.strftime("%Y%m%d_%H%M%S")}
   Use XHR to load /api/vsp/runs (avoid window.fetch wrappers). Never kill dashboard.
*/
(function(){{
  try{{
    if (window.__{MARK}__) return; window.__{MARK}__=true;

    function xhrJson(url, timeoutMs){{
      return new Promise(function(resolve,reject){{
        try{{
          var x=new XMLHttpRequest();
          x.open("GET", url, true);
          x.timeout=timeoutMs||8000;
          x.setRequestHeader("Cache-Control","no-store");
          x.setRequestHeader("Pragma","no-cache");
          x.onreadystatechange=function(){{
            if (x.readyState!==4) return;
            if ((x.status||0)!==200) return reject({{status:x.status||0}});
            try{{ resolve(JSON.parse(x.responseText||"{{}}")); }}
            catch(e){{ reject({{status:598}}); }}
          }};
          x.ontimeout=function(){{ reject({{status:599}}); }};
          x.onerror=function(){{ reject({{status:597}}); }};
          x.send();
        }}catch(e){{ reject({{status:596}}); }}
      }});
    }}

    function ensureBanner(msg){{
      try{{
        var id="vsp_degraded_banner_v3";
        var el=document.getElementById(id);
        if(!el){{
          el=document.createElement("div");
          el.id=id;
          el.className="vsp-degraded-banner";
          (document.querySelector(".vsp-card,.card,.panel,.box")||document.body).prepend(el);
        }}
        el.textContent=msg;
      }}catch(_){}
    }}

    async function run(){{
      var path=(location.pathname||"");
      if(!path.includes("vsp5")) return;

      try{{
        var runs=await xhrJson("/api/vsp/runs?limit=1&_ts="+Date.now(), 8000);
        if(runs && runs.ok && runs.rid_latest){{
          window.__VSP_RID_LATEST__ = runs.rid_latest;
          return;
        }}
        ensureBanner("DEGRADED: runs api non-ok (UI continues)");
      }}catch(e){{
        ensureBanner("DEGRADED: cannot load runs via XHR (status="+(e&&e.status)+") (UI continues)");
      }}
    }}

    if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  }}catch(_){}
}})();
"""
p.write_text(s + "\n" + inject + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

# 4) restart
echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh >/dev/null 2>&1 || true
fi

echo "== verify =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_theme_override_p1_v2.css" | head -n 2 || true
echo "[NEXT] Mở Incognito /vsp5 hoặc Ctrl+F5."
