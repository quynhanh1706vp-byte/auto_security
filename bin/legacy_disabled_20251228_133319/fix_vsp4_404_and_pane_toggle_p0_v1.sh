#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

echo "== (1) Write pane toggle JS (safe if panes not found) =="
JS="static/js/vsp_pane_toggle_safe_v1.js"
cp -f "$JS" "$JS.bak_${TS}" 2>/dev/null || true
cat > "$JS" <<'JS'
/* VSP_PANE_TOGGLE_SAFE_V1: hide non-active panes based on hash route */
(function(){
  'use strict';

  function routeFromHash(h){
    h = (h||'').trim();
    if (!h) return 'dashboard';
    if (h[0] === '#') h = h.slice(1);
    // strip query-ish fragments: #runs&x=y or #runs?x=y
    h = h.split('&')[0].split('?')[0].trim();
    return h || 'dashboard';
  }

  function firstExistingId(ids){
    for (const id of ids){
      const el = document.getElementById(id);
      if (el) return el;
    }
    return null;
  }

  function setPaneVisible(pane, on){
    if (!pane) return;
    pane.style.display = on ? '' : 'none';
    pane.setAttribute('data-vsp-pane-visible', on ? '1' : '0');
  }

  function apply(){
    try{
      const r = routeFromHash(location.hash);
      const map = {
        dashboard: ['pane-dashboard','dashboard-pane','vsp-pane-dashboard'],
        runs:      ['pane-runs','runs-pane','vsp-pane-runs'],
        datasource:['pane-datasource','datasource-pane','vsp-pane-datasource'],
        settings:  ['pane-settings','settings-pane','vsp-pane-settings'],
        rules:     ['pane-rules','rules-pane','vsp-pane-rules'],
      };

      // show/hide panes if they exist
      const panes = {};
      Object.keys(map).forEach(k => panes[k] = firstExistingId(map[k]));
      Object.keys(panes).forEach(k => setPaneVisible(panes[k], k === r));

      // also mark active tab if present
      document.querySelectorAll('.vsp-tab,[data-tab]').forEach(a=>{
        const t = (a.getAttribute('data-tab') || (a.getAttribute('href')||'').replace('#','')).split('&')[0].split('?')[0];
        if (!t) return;
        if (t === r) a.classList.add('is-active');
        else a.classList.remove('is-active');
      });
    }catch(e){
      try{ console.warn("[VSP_PANE_TOGGLE_SAFE_V1] apply failed", e); }catch(_){}
    }
  }

  window.addEventListener('hashchange', apply, {passive:true});
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply);
  else apply();
})();
JS
node --check "$JS" >/dev/null && echo "[OK] node --check: $JS"

echo "== (2) Ensure template loads pane toggle JS =="
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_panefix_${TS}" && echo "[BACKUP] $TPL.bak_panefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time
tpl=Path("templates/vsp_dashboard_2025.html")
s=tpl.read_text(encoding="utf-8", errors="ignore")
if "vsp_pane_toggle_safe_v1.js" in s:
    print("[OK] pane toggle already in template")
else:
    tag=f'<script src="/static/js/vsp_pane_toggle_safe_v1.js?v={int(time.time())}"></script>\n'
    # insert near end of <head> if possible, else prepend
    m=re.search(r"</head\s*>", s, flags=re.I)
    if m:
        s = s[:m.start()] + tag + s[m.start():]
    else:
        s = tag + s
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected pane toggle tag into template")
PY

echo "== (3) Sanitize stray script src like P251217_065927 via after_request (removes noisy 404) =="
PYF="vsp_demo_app.py"
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }
cp -f "$PYF" "$PYF.bak_htmlsanitize_${TS}" && echo "[BACKUP] $PYF.bak_htmlsanitize_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

m=re.search(r'^\s*(\w+)\s*=\s*Flask\s*\(', s, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find app = Flask(...) in vsp_demo_app.py")
appvar=m.group(1)

if "VSP_VSP4_HTML_SANITIZE_P0_V1" in s:
    print("[OK] sanitize already present")
else:
    s += f"""

# ================================
# VSP_VSP4_HTML_SANITIZE_P0_V1
# - remove stray <script src="P\\d{{6}}_\\d{{6}}..."> which causes noisy 404
# ================================
@{appvar}.after_request
def __vsp_vsp4_html_sanitize_p0_v1(resp):
  try:
    pth = (request.path or "")
    if pth not in ("/vsp4", "/vsp4/"):
      return resp
    ct = (resp.content_type or "")
    if "text/html" not in ct:
      return resp
    html = resp.get_data(as_text=True)
    # remove broken/stray script tags like: <script src="P251217_065927"></script>
    html2 = re.sub(r'<script\\s+[^>]*src="P\\d{{6}}_\\d{{6}}[^"]*"[^>]*>\\s*</script>\\s*', '', html, flags=re.I)
    if html2 != html:
      resp.set_data(html2)
  except Exception:
    pass
  return resp
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended after_request sanitize on", appvar)

PY

python3 -m py_compile "$PYF" && echo "[OK] py_compile OK: $PYF"

echo "== (4) Restart 8910 (NO restore) =="
if [ -x bin/ui_restart_8910_no_restore_v1.sh ]; then
  bash bin/ui_restart_8910_no_restore_v1.sh
else
  PIDF="out_ci/ui_8910.pid"
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.6
  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 120 --graceful-timeout 30 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid "$PIDF" \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    >/dev/null 2>&1 & disown || true
fi

echo "== (5) Verify: no stray P******_****** script in HTML =="
curl -sS http://127.0.0.1:8910/vsp4 | grep -nE 'src="P[0-9]{6}_[0-9]{6}' || echo "[OK] no stray P* script tags"

echo "[NEXT] Ctrl+Shift+R rồi mở:"
echo "  http://127.0.0.1:8910/vsp4/#runs"
echo "  http://127.0.0.1:8910/vsp4/#dashboard"
echo "  http://127.0.0.1:8910/vsp4/#datasource"
echo "Check Network: cái 404 P251217_065927 phải biến mất, và #runs không còn lòi dashboard pane."
