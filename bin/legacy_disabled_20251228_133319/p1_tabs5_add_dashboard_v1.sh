#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && NODE_OK=1 || NODE_OK=0
command -v systemctl >/dev/null 2>&1 && SYS_OK=1 || SYS_OK=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_tabs4_autorid_v1.js"
MARK="VSP_P1_TABS5_ADD_DASHBOARD_V1"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_tabs5_${TS}"
echo "[BACKUP] ${JS}.bak_tabs5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_tabs4_autorid_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_TABS5_ADD_DASHBOARD_V1"

if mark in s:
    print("[OK] already patched:", mark)
else:
    # 1) Try inject into TABS array if exists
    m = re.search(r'(\b(?:const|let|var)\s+TABS\s*=\s*\[)(.*?)(\]\s*;)', s, flags=re.S)
    if m:
        body = m.group(2)
        if "/vsp5" in body:
            print("[OK] TABS already contains /vsp5")
        else:
            dash = '{ id:"dashboard", label:"Dashboard", href:"/vsp5" },\n'
            new_body = dash + body
            s = s[:m.start(2)] + new_body + s[m.end(2):]
            print("[OK] injected dashboard into TABS[]")
    else:
        print("[WARN] TABS[] not found; will rely on DOM injection fallback")

    # 2) Always add safe DOM injection fallback (idempotent)
    inject = r'''
/* ''' + mark + r''' (fallback DOM injection: ensure Dashboard tab exists) */
(function(){
  try{
    // If already has dashboard link => done
    if(document.querySelector('a[href="/vsp5"],a[href="/dashboard"]')) return;

    const nav =
      document.querySelector('#vspTabs') ||
      document.querySelector('.vsp-tabs') ||
      document.querySelector('nav.vsp') ||
      document.querySelector('.topbar nav') ||
      document.querySelector('nav');

    if(!nav) return;

    const a = document.createElement('a');
    a.href = '/vsp5';
    a.textContent = 'Dashboard';
    a.className = (a.className || '') + ' vsp-tab vsp-tab-dashboard';
    nav.insertBefore(a, nav.firstChild);
  }catch(_){}
})();
 /* /''' + mark + r''' */
'''
    s = s.rstrip() + "\n\n" + inject + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] patched:", mark)
PY

# Patch /vsp5 template: ensure it includes vsp_tabs4_autorid_v1.js + vsp_topbar_commercial_v1.js
# We'll patch common candidate templates: vsp_5tabs_enterprise_v2.html and vsp_dashboard_2025.html
for TPL in templates/vsp_5tabs_enterprise_v2.html templates/vsp_dashboard_2025.html; do
  [ -f "$TPL" ] || continue
  cp -f "$TPL" "${TPL}.bak_tabs5_${TS}"
  echo "[BACKUP] ${TPL}.bak_tabs5_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

tpl = Path("'"$TPL"'")
s = tpl.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P1_TABS5_ADD_DASHBOARD_V1"

def ensure_script(src):
    # accept either with v=... or plain, so we don't duplicate
    return (src in s) or (src.split("?")[0] in s)

need_tabs = '/static/js/vsp_tabs4_autorid_v1.js'
need_topbar = '/static/js/vsp_topbar_commercial_v1.js'

# Use the same asset_v pattern style used elsewhere; server-side should render numeric v, avoiding {{asset_v}} leakage.
tabs_tag = '<script src="/static/js/vsp_tabs4_autorid_v1.js?v={{ asset_v|default(\'\') }}"></script>'
topbar_tag = '<script src="/static/js/vsp_topbar_commercial_v1.js?v={{ asset_v|default(\'\') }}"></script>'

to_add = []
if not ensure_script(need_tabs): to_add.append(tabs_tag)
if not ensure_script(need_topbar): to_add.append(topbar_tag)

if not to_add:
    print("[OK] template already includes tabs/topbar:", tpl.name)
else:
    # Insert before </head> if possible, else append at end
    ins = "\n".join(to_add) + f"\n<!-- {mark} -->\n"
    if "</head>" in s:
        s = s.replace("</head>", ins + "</head>", 1)
    else:
        s = s + "\n" + ins
    tpl.write_text(s, encoding="utf-8")
    print("[OK] injected into template:", tpl.name, "added=", len(to_add))
PY
done

if [ "$NODE_OK" = "1" ]; then
  node --check "$JS" >/dev/null && echo "[OK] node --check ok: $JS" || { echo "[ERR] node --check failed: $JS"; exit 3; }
fi

if [ "$SYS_OK" = "1" ]; then
  systemctl restart "$SVC" 2>/dev/null && echo "[OK] restarted: $SVC" || echo "[WARN] restart skipped/failed: $SVC"
fi

echo "[DONE] Tabs5 patch applied (JS + /vsp5 templates)."
