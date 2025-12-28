#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node
command -v systemctl >/dev/null 2>&1 || true

JS="static/js/vsp_data_source_lazy_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_ds_itemsfb_${TS}"
echo "[BACKUP] ${JS}.bak_ds_itemsfb_${TS}"

python3 - "$JS" <<'PY'
import sys,re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()
if "VSP_P2_DS_ITEMS_FALLBACK_V1" in s:
    print("[OK] already patched"); raise SystemExit(0)

# very tolerant: wherever we build list from response, enforce fallback order
# findings -> items -> data, and also check nested data.findings/items/data
patch = r'''
/* VSP_P2_DS_ITEMS_FALLBACK_V1 */
function __vspPickArr(j){
  try{
    if(!j) return [];
    const f = j.findings;
    if(Array.isArray(f) && f.length) return f;
    const it = j.items;
    if(Array.isArray(it) && it.length) return it;
    const dt = j.data;
    if(Array.isArray(dt) && dt.length) return dt;
    if(j.data && typeof j.data === "object"){
      const df=j.data.findings; if(Array.isArray(df) && df.length) return df;
      const di=j.data.items;    if(Array.isArray(di) && di.length) return di;
      const dd=j.data.data;     if(Array.isArray(dd) && dd.length) return dd;
    }
  }catch(e){}
  return [];
}
/* /VSP_P2_DS_ITEMS_FALLBACK_V1 */
'''

# Insert helper near top (after first "use strict" or at beginning)
m=re.search(r'(["\']use strict["\'];\s*)', s)
if m:
    s = s[:m.end()] + "\n" + patch + "\n" + s[m.end():]
else:
    s = patch + "\n" + s

# Replace common patterns "j.findings || []" / "j.data || []" with __vspPickArr(j)
s = re.sub(r'\b(j)\.findings\s*\|\|\s*\[\s*\]', r'__vspPickArr(\1)', s)
s = re.sub(r'\b(j)\.items\s*\|\|\s*\[\s*\]', r'__vspPickArr(\1)', s)
s = re.sub(r'\b(j)\.data\s*\|\|\s*\[\s*\]', r'__vspPickArr(\1)', s)

open(p,"w",encoding="utf-8").write(s)
print("[OK] patched DS to use findings/items/data fallback")
PY

node -c "$JS" >/dev/null
echo "[OK] node -c OK"
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
