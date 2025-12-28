#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
V="cio_${TS}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need curl; need head

mkdir -p static/css static/js

echo "== [1] Write CIO shell CSS =="
CSS="static/css/vsp_cio_shell_v1.css"
cp -f "$CSS" "${CSS}.bak_${TS}" 2>/dev/null || true
cat > "$CSS" <<'CSS'
/* VSP CIO Shell v1 (commercial polish) */
:root{
  --bg0:#0b1220;
  --bg1:#0f172a;
  --card:#0b1326;
  --card2:#0c162c;
  --line:rgba(148,163,184,.16);
  --muted:#94a3b8;
  --text:#e5e7eb;
  --text2:#cbd5e1;
  --accent:#60a5fa;
  --good:#22c55e;
  --warn:#f59e0b;
  --bad:#ef4444;
  --shadow: 0 10px 30px rgba(0,0,0,.35);
  --radius:16px;
  --pad:16px;
  --pad2:24px;
  --max: 1280px;
  --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace;
  --sans: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, "Apple Color Emoji","Segoe UI Emoji";
}

html,body{
  background: radial-gradient(1200px 700px at 10% -10%, rgba(96,165,250,.16), transparent 55%),
              radial-gradient(900px 600px at 90% -20%, rgba(34,197,94,.10), transparent 55%),
              var(--bg0);
  color: var(--text);
  font-family: var(--sans);
}

a{ color: var(--accent); text-decoration: none; }
a:hover{ text-decoration: underline; }

.vsp-cio-wrap{
  max-width: var(--max);
  margin: 0 auto;
  padding: 18px 18px 32px 18px;
}

/* topbar safe polish */
.vsp-topbar, #vsp_topbar, .topbar{
  position: sticky;
  top: 0;
  z-index: 50;
  backdrop-filter: blur(10px);
  background: rgba(15,23,42,.78);
  border-bottom: 1px solid var(--line);
}

/* cards */
.vsp-card{
  background: linear-gradient(180deg, rgba(12,22,44,.92), rgba(11,19,38,.92));
  border: 1px solid var(--line);
  border-radius: var(--radius);
  box-shadow: var(--shadow);
}

/* normalize inline padding on tab root */
#vsp_tab_root{
  padding: 0 !important;
}

/* common blocks */
.vsp-block{
  border: 1px solid var(--line);
  border-radius: var(--radius);
  background: rgba(11,19,38,.72);
  box-shadow: 0 8px 22px rgba(0,0,0,.25);
}

/* tables */
table{
  border-collapse: collapse;
  width: 100%;
}
th, td{
  border-bottom: 1px solid rgba(148,163,184,.14);
  padding: 10px 10px;
  font-size: 13px;
  color: var(--text2);
}
th{
  font-size: 12px;
  letter-spacing: .02em;
  text-transform: uppercase;
  color: var(--muted);
  background: rgba(15,23,42,.55);
  position: sticky;
  top: 0;
  z-index: 5;
}
tr:hover td{
  background: rgba(96,165,250,.06);
}

/* buttons */
button, .btn, .vsp-btn{
  background: rgba(96,165,250,.12);
  color: var(--text);
  border: 1px solid rgba(96,165,250,.25);
  padding: 8px 12px;
  border-radius: 12px;
  cursor: pointer;
  transition: transform .06s ease, background .15s ease;
}
button:hover, .btn:hover, .vsp-btn:hover{
  background: rgba(96,165,250,.18);
}
button:active, .btn:active, .vsp-btn:active{
  transform: translateY(1px);
}

/* badges */
.vsp-badge{
  display:inline-flex;
  align-items:center;
  gap:6px;
  padding: 4px 10px;
  border-radius: 999px;
  border: 1px solid var(--line);
  background: rgba(2,6,23,.35);
  font-size: 12px;
  color: var(--text2);
}
CSS

echo "== [2] Write CIO apply JS (wrap root + set body class) =="
JS="static/js/vsp_cio_shell_apply_v1.js"
cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true
cat > "$JS" <<'JS'
(function(){
  try{
    document.documentElement.classList.add("vsp-cio");
    document.body.classList.add("vsp-cio");

    function wrap(el){
      if(!el) return;
      // avoid double wrap
      if(el.closest(".vsp-cio-wrap")) return;
      const w=document.createElement("div");
      w.className="vsp-cio-wrap";
      el.parentNode.insertBefore(w, el);
      w.appendChild(el);
    }

    // wrap known roots
    wrap(document.getElementById("vsp-dashboard-main"));
    wrap(document.getElementById("vsp-runs-main"));
    wrap(document.getElementById("vsp-data-source-main"));
    wrap(document.getElementById("vsp-settings-main"));
    wrap(document.getElementById("vsp-rule-overrides-main"));
    wrap(document.getElementById("vsp_tab_root"));

    // mark blocks/cards if needed (non-breaking)
    document.querySelectorAll(".card,.kpi-card,.panel,.box").forEach(el=>{
      if(!el.classList.contains("vsp-card")) el.classList.add("vsp-card");
    });
  }catch(e){}
})();
JS

echo "== [3] Inject CSS+JS into ALL templates (idempotent) =="
python3 - <<PY
from pathlib import Path
import re, time

v="$V"
root=Path("templates")
files=list(root.rglob("*.html"))
if not files:
    raise SystemExit("[ERR] no templates found")

css_tag=f'<link rel="stylesheet" href="/static/css/vsp_cio_shell_v1.css?v={v}"/>'
js_tag=f'<script defer src="/static/js/vsp_cio_shell_apply_v1.js?v={v}"></script>'

patched=0
for p in files:
    s=p.read_text(encoding="utf-8", errors="replace")
    s0=s

    if "vsp_cio_shell_v1.css" not in s:
        # insert before </head>
        s=re.sub(r'(</head\s*>)', css_tag+r'\n\1', s, flags=re.I)

    if "vsp_cio_shell_apply_v1.js" not in s:
        # insert before </body> (preferred), else before </html>
        if re.search(r'</body\s*>', s, flags=re.I):
            s=re.sub(r'(</body\s*>)', js_tag+r'\n\1', s, flags=re.I)
        else:
            s=re.sub(r'(</html\s*>)', js_tag+r'\n\1', s, flags=re.I)

    if s!=s0:
        bak=p.with_name(p.name+f".bak_cio_shell_{time.strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(s0, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        patched += 1

print("[OK] templates_patched=", patched, "of", len(files))
PY

echo "== [4] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [5] Smoke: ensure CSS/JS referenced on key pages =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "== $p =="
  curl -fsS --max-time 3 --range 0-120000 "$BASE$p" | grep -n "vsp_cio_shell_v1.css\|vsp_cio_shell_apply_v1.js" | head -n 5 || true
done

echo "[DONE] Ctrl+Shift+R on browser."
