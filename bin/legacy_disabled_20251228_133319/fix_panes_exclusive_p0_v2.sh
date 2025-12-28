#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) write pane toggle v2 (hide dashboard on non-dashboard routes) =="
JS="static/js/vsp_pane_toggle_safe_v2.js"
mkdir -p static/js
cp -f "$JS" "$JS.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* VSP_PANE_TOGGLE_SAFE_V2: show ONLY active pane by hash route */
(function(){
  'use strict';

  function routeFromHash(){
    let h = (location.hash||"").trim();
    if (!h) return "dashboard";
    if (h[0] === "#") h = h.slice(1);
    h = h.split(/[?&]/)[0].trim();
    if (!h) return "dashboard";
    // normalize aliases
    if (h === "run" || h === "reports") h = "runs";
    if (h === "artifacts") h = "datasource";
    return h;
  }

  const map = {
    dashboard: "vsp-dashboard-main",
    runs:      "vsp-runs-main",
    datasource:"vsp-datasource-main",
    settings:  "vsp-settings-main",
    rules:     "vsp-rules-main"
  };

  function setDisplay(id, on){
    const el = document.getElementById(id);
    if (!el) return;
    el.style.display = on ? "" : "none";
  }

  function apply(){
    const r = routeFromHash();
    const activeId = map[r] || map.dashboard;

    // hide all known panes
    Object.values(map).forEach(id => setDisplay(id, false));

    // show active
    setDisplay(activeId, true);

    // extra safety: if non-dashboard route, force hide dashboard even if DOM duplicated
    if (r !== "dashboard") {
      setDisplay(map.dashboard, false);
      // also hide any stray dashboard blocks if they exist
      document.querySelectorAll('[data-pane="dashboard"], .vsp-dashboard-pane, .vsp-dashboard-main').forEach(x=>{
        try{ x.style.display = "none"; }catch(_){}
      });
    }
  }

  window.addEventListener("hashchange", apply);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply, {once:true});
  } else apply();

  // late apply for async injected panes
  setTimeout(apply, 200);
  setTimeout(apply, 800);
})();
JS

node --check "$JS" >/dev/null && echo "[OK] node --check: $JS"

echo "== (2) inject pane toggle v2 into template =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_panetogglev2_${TS}" && echo "[BACKUP] $TPL.bak_panetogglev2_${TS}"

python3 - <<'PY'
from pathlib import Path
import time, re
tpl=Path("templates/vsp_dashboard_2025.html")
s=tpl.read_text(encoding="utf-8", errors="ignore")

# remove old v1 tag if any
s = re.sub(r'<script[^>]+vsp_pane_toggle_safe_v1\.js[^>]*>\s*</script>\s*', '', s, flags=re.I)

tag = f'<script src="/static/js/vsp_pane_toggle_safe_v2.js?v={int(time.time())}"></script>\n'
if "vsp_pane_toggle_safe_v2.js" in s:
    print("[OK] already has v2 tag")
else:
    # inject near other UI loader tags (or just after <head>)
    m=re.search(r'(?is)<head[^>]*>\s*', s)
    if m:
        i=m.end()
        s = s[:i] + "  " + tag + s[i:]
    else:
        s = tag + s
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected v2 tag")
PY

echo "== (3) restart 8910 (NO restore) =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "[NEXT] Ctrl+Shift+R rồi test:"
echo "  http://127.0.0.1:8910/vsp4/#runs"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
echo "Kỳ vọng: chỉ hiện pane của tab, không còn lòi Dashboard pane dưới."
