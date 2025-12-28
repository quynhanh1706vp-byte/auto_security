#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need grep; need find; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

# --- 1) Write CSS override (contrast + button readability) ---
CSS_DIR="static/css"
OVR="${CSS_DIR}/vsp_theme_override_p1_v2.css"
mkdir -p "$CSS_DIR"
cat > "$OVR" <<'CSS'
/* vsp_theme_override_p1_v2.css */
/* Goal: tăng contrast, chữ sáng hơn, nút/link dễ đọc, table hover rõ */
:root{
  --vsp-bg0:#070a12;
  --vsp-bg1:#0b1020;
  --vsp-bg2:#0f1830;
  --vsp-card:#0e1528;
  --vsp-card2:#0b1222;
  --vsp-text:#e8eefc;
  --vsp-muted:#a8b3d6;
  --vsp-line:rgba(255,255,255,.08);
  --vsp-accent:#6ea8ff;
  --vsp-accent2:#8a7dff;
  --vsp-danger:#ff5d6c;
  --vsp-warn:#ffcc66;
  --vsp-ok:#57e3a3;
}

html, body{
  background: radial-gradient(1200px 700px at 30% 10%, rgba(110,168,255,.12), transparent 60%),
              radial-gradient(900px 600px at 70% 15%, rgba(138,125,255,.10), transparent 55%),
              linear-gradient(180deg, var(--vsp-bg1), var(--vsp-bg0));
  color: var(--vsp-text);
}

a, .link, .btn-link{
  color: var(--vsp-accent) !important;
  text-decoration: none;
}
a:hover{ text-decoration: underline; }

.vsp-topbar, .topbar, .navbar{
  backdrop-filter: blur(10px);
  background: rgba(10,16,32,.72) !important;
  border-bottom: 1px solid var(--vsp-line) !important;
}

.vsp-card, .card, .panel, .box{
  background: linear-gradient(180deg, rgba(14,21,40,.88), rgba(9,14,30,.88)) !important;
  border: 1px solid var(--vsp-line) !important;
  box-shadow: 0 10px 24px rgba(0,0,0,.35) !important;
}

.badge, .pill{
  border: 1px solid var(--vsp-line) !important;
  background: rgba(255,255,255,.05) !important;
  color: var(--vsp-text) !important;
}

button, .btn{
  border: 1px solid rgba(255,255,255,.10) !important;
  background: rgba(255,255,255,.06) !important;
  color: var(--vsp-text) !important;
}
button:hover, .btn:hover{
  background: rgba(255,255,255,.10) !important;
}
.btn-primary{
  background: rgba(110,168,255,.20) !important;
  border-color: rgba(110,168,255,.35) !important;
}
.btn-danger{
  background: rgba(255,93,108,.18) !important;
  border-color: rgba(255,93,108,.35) !important;
}

input, textarea, select{
  background: rgba(255,255,255,.04) !important;
  border: 1px solid rgba(255,255,255,.12) !important;
  color: var(--vsp-text) !important;
}
input::placeholder, textarea::placeholder{ color: rgba(232,238,252,.45) !important; }

table, .table{
  border-color: var(--vsp-line) !important;
}
tr:hover, .row:hover{
  background: rgba(110,168,255,.07) !important;
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

# --- 2) Patch templates: ensure ONE cache-bust for boot js + include CSS override ---
python3 - <<PY
from pathlib import Path
import re, time
ts="${TS}"

tpls = [
  "templates/vsp_5tabs_enterprise_v2.html",
  "templates/vsp_dashboard_2025.html",
  "templates/vsp_data_source_v1.html",
  "templates/vsp_rule_overrides_v1.html",
]
css_href = f'/static/css/vsp_theme_override_p1_v2.css?v={ts}'
js_pat = re.compile(r'(/static/js/vsp_p1_page_boot_v1\\.js)(\\?v=[^"\\\']*)?')

changed=[]
for t in tpls:
  p=Path(t)
  if not p.exists():
    continue
  s=p.read_text(encoding="utf-8", errors="replace")
  s0=s

  # Normalize boot js src -> exactly ?v=TS
  def _repl(m):
    return f'{m.group(1)}?v={ts}'
  s = re.sub(r'(/static/js/vsp_p1_page_boot_v1\\.js)(\\?v=[^"\\\']*)?', _repl, s)

  # Ensure we don't have double ?v=... ?v=...
  s = re.sub(r'(/static/js/vsp_p1_page_boot_v1\\.js\\?v=[^"\\\']*)\\?v=[^"\\\']*', r'\1', s)

  # Inject CSS link if missing
  if "vsp_theme_override_p1_v2.css" not in s:
    link = f'\\n<link rel="stylesheet" href="{css_href}">\\n'
    # Try insert before closing </head>
    if "</head>" in s:
      s = s.replace("</head>", link + "</head>", 1)
    else:
      # fallback: insert near top
      s = link + s

  if s != s0:
    bak = p.with_suffix(p.suffix + f".bak_finish_{ts}")
    bak.write_text(s0, encoding="utf-8")
    p.write_text(s, encoding="utf-8")
    changed.append(p.as_posix())

print("[OK] templates patched:", len(changed))
for x in changed:
  print(" -", x)
PY

# --- 3) Patch boot JS: add XHR runs loader to eliminate fetch-wrapper 503 ---
cp -f "$JS" "${JS}.bak_finish_${TS}"
echo "[BACKUP] ${JS}.bak_finish_${TS}"

python3 - <<'PY'
from pathlib import Path
import time
p=Path("static/js/vsp_p1_page_boot_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_XHR_RUNS_FALLBACK_V2"

if MARK in s:
  print("[OK] marker already present:", MARK)
  raise SystemExit(0)

inject = r"""
/* VSP_P1_XHR_RUNS_FALLBACK_V2 {{TS}}
   Purpose: dashboard MUST NOT die if fetch wrapper/cached JS causes false 503.
   Strategy: use XMLHttpRequest (bypass window.fetch wrappers), retry, and remove "Failed to load" banner.
*/
(function(){
  try{
    if (window.__VSP_P1_XHR_RUNS_FALLBACK_V2__) return;
    window.__VSP_P1_XHR_RUNS_FALLBACK_V2__ = true;

    function xhrJson(url, timeoutMs){
      return new Promise(function(resolve, reject){
        try{
          var x = new XMLHttpRequest();
          x.open("GET", url, true);
          x.timeout = timeoutMs || 8000;
          x.setRequestHeader("Cache-Control","no-store");
          x.setRequestHeader("Pragma","no-cache");
          x.onreadystatechange = function(){
            if (x.readyState !== 4) return;
            var st = x.status || 0;
            if (st !== 200){
              return reject({status: st, body: (x.responseText||"").slice(0,200)});
            }
            try{
              var j = JSON.parse(x.responseText || "{}");
              resolve(j);
            }catch(e){
              reject({status: 598, body: (x.responseText||"").slice(0,200), err: String(e)});
            }
          };
          x.ontimeout = function(){ reject({status: 599, body:"timeout"}); };
          x.onerror = function(){ reject({status: 597, body:"xhr_error"}); };
          x.send();
        }catch(e){
          reject({status: 596, body:String(e)});
        }
      });
    }

    async function retry(fn, n){
      var last;
      for (var i=0;i<n;i++){
        try{ return await fn(i); }catch(e){ last=e; await new Promise(r=>setTimeout(r, 250*(i+1))); }
      }
      throw last;
    }

    function removeFailedBanner(){
      try{
        var nodes = Array.from(document.querySelectorAll("*"));
        for (var i=0;i<nodes.length;i++){
          var t = (nodes[i].innerText||"").trim();
          if (!t) continue;
          if (t.includes("Failed to load dashboard data") || t.includes("HTTP 503") && t.includes("/api/vsp/runs")){
            // hide the nearest block
            nodes[i].style.display = "none";
          }
        }
      }catch(_){}
    }

    function ensureDegradedBanner(msg){
      try{
        var host = document.querySelector(".vsp-card, .card, .panel, .box") || document.body;
        var id = "vsp_degraded_banner_v2";
        var el = document.getElementById(id);
        if (!el){
          el = document.createElement("div");
          el.id = id;
          el.className = "vsp-degraded-banner";
          el.innerText = msg;
          host.insertBefore(el, host.firstChild);
        }else{
          el.innerText = msg;
        }
      }catch(_){}
    }

    async function run(){
      // only for vsp5 dashboard page
      var path = (location.pathname||"");
      if (!path.includes("vsp5")) return;

      // always attempt runs via XHR with cache-bust
      try{
        var runs = await retry(function(i){
          return xhrJson("/api/vsp/runs?limit=1&_ts=" + Date.now() + "_" + i, 8000);
        }, 3);

        if (runs && runs.ok && runs.rid_latest){
          window.__VSP_RID_LATEST__ = runs.rid_latest;

          // remove stale error banners
          removeFailedBanner();

          // optional: also update any top badge that contains rid_latest=
          try{
            var spans = Array.from(document.querySelectorAll("span,div,a,button"));
            spans.forEach(function(n){
              var tx=(n.textContent||"");
              if (tx.includes("rid_latest=")){
                n.textContent = tx.replace(/rid_latest=[^\\s]+/g, "rid_latest=" + runs.rid_latest);
              }
            });
          }catch(_){}

          return;
        }

        // runs returned but not ok
        ensureDegradedBanner("DEGRADED: runs api returned non-ok. (UI will continue)");
      }catch(e){
        // hard fail: still don't kill dashboard
        removeFailedBanner();
        ensureDegradedBanner("DEGRADED: cannot load runs via XHR. status=" + (e && e.status) + " (UI will continue)");
      }
    }

    if (document.readyState === "loading"){
      document.addEventListener("DOMContentLoaded", run);
    }else{
      run();
    }
  }catch(_){}
})();
""".replace("{{TS}}", time.strftime("%Y%m%d_%H%M%S"))

p.write_text(s + "\n" + inject + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

# --- 4) Restart (prefer your existing launcher if present) ---
echo "[OK] restart UI"
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh
else
  # best-effort: kill port and start minimal
  fuser -k 8910/tcp >/dev/null 2>&1 || true
  nohup ./.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    > out_ci/ui_8910.boot.log 2>&1 &
  sleep 0.8
fi

echo "== verify =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 2 || true
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_theme_override_p1_v2.css" | head -n 2 || true
echo "[NEXT] Mở Incognito /vsp5 (khuyến nghị) hoặc Ctrl+F5 để chắc chắn hết cache."
