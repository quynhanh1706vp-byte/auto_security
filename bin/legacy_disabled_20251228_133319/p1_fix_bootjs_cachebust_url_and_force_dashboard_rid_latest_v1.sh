#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need jq

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

# 1) Fix templates: script src must be exactly "...js?v=<TS>" (ONE query only)
python3 - "$TS" <<'PY'
import sys, re
from pathlib import Path
ts=sys.argv[1]
tpl=Path("templates")
changed=[]
for p in tpl.rglob("*.html"):
    s=p.read_text(encoding="utf-8", errors="replace")
    if "vsp_p1_page_boot_v1.js" not in s:
        continue

    # normalize any previous cachebust mistakes: keep only ONE ?v=
    s2=re.sub(r'vsp_p1_page_boot_v1\.js[^"]*',
              f'vsp_p1_page_boot_v1.js?v={ts}',
              s)

    if s2!=s:
        p.write_text(s2, encoding="utf-8")
        changed.append(str(p))
print(f"[OK] templates fixed: {len(changed)}")
for x in changed[:50]:
    print(" -", x)
PY

# 2) Append a tiny JS patch to force dashboard label "Latest RID" = rid_latest
cp -f "$JS" "${JS}.bak_force_latest_${TS}"
echo "[BACKUP] ${JS}.bak_force_latest_${TS}"

python3 - "$JS" "$TS" <<'PY'
import sys
from pathlib import Path

js_path=Path(sys.argv[1]); ts=sys.argv[2]
s=js_path.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_FORCE_DASHBOARD_LATEST_RID_V1"
if MARK in s:
    print("[OK] marker already present"); sys.exit(0)

patch = f"""
/* {MARK} {ts}
   Goal: Dashboard 'Latest RID' must follow /api/vsp/runs rid_latest (ignore old cached rid text)
*/
(function(){{
  async function _vspFetchJSON(url){{
    const r = await fetch(url, {{cache:'no-store', credentials:'same-origin'}});
    if(!r.ok) throw new Error('HTTP '+r.status+' '+url);
    return await r.json();
  }}

  function _setTextIf(el, txt){{ try{{ if(el && typeof txt==='string' && txt) el.textContent = txt; }}catch(e){{}} }}

  async function _forceLatestRidOnPage(){{
    let j=null;
    try{{ j = await _vspFetchJSON('/api/vsp/runs?limit=1'); }}catch(e){{ return; }}
    const rid = (j && (j.rid_latest || (j.items && j.items[0] && j.items[0].run_id))) || null;
    if(!rid) return;

    // overwrite common cache keys (best-effort)
    try{{ localStorage.setItem('vsp_active_rid', rid); }}catch(e){{}}
    try{{ localStorage.setItem('vsp_latest_rid', rid); }}catch(e){{}}

    // 1) update known selectors if exist
    document.querySelectorAll('#latestRid,.latest-rid,.vsp-latest-rid,[data-latest-rid]')
      .forEach(el => _setTextIf(el, rid));

    // 2) heuristic: find "Latest RID" label and replace nearby rid-looking text
    const labs=[...document.querySelectorAll('*')].filter(el => (el.textContent||'').trim()==='Latest RID');
    for(const lab of labs){{
      const scope = lab.closest('div') || lab.parentElement;
      if(!scope) continue;
      const cand=[...scope.querySelectorAll('*')].find(e => /(^|\\b)([A-Za-z0-9_-]+_RUN_|RUN_)/.test((e.textContent||'').trim()));
      if(cand) _setTextIf(cand, rid);
    }}

    // 3) also update any header chip that contains old rid
    const chips=[...document.querySelectorAll('*')].filter(el => /RUN_/.test((el.textContent||'')) && (el.textContent||'').length<120);
    for(const c of chips){{
      if((c.textContent||'').includes('btl86-') || (c.textContent||'').includes('_RUN_')) {{
        // only update the ones that look like "rid:" or "VSP_*"
        if(/VSP_|rid|RUN/.test(c.textContent||'')) _setTextIf(c, c.textContent.replace(/\\S*RUN_\\d{{8}}_\\d{{6}}\\S*/g, rid));
      }}
    }}
  }}

  document.addEventListener('DOMContentLoaded', function(){{
    setTimeout(_forceLatestRidOnPage, 80);
  }});
}})();
"""
js_path.write_text(s + "\n" + patch + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== verify: vsp5 script src =="
curl -sS http://127.0.0.1:8910/vsp5 | grep -n "vsp_p1_page_boot_v1.js" | head -n 3 || true

echo "== verify: rid_latest =="
curl -sS http://127.0.0.1:8910/api/vsp/runs?limit=1 | jq -r '.rid_latest,.items[0].run_id' || true

echo "[NEXT] Browser: Ctrl+F5 /vsp5 or open Incognito"
