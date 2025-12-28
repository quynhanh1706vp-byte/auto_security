#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_data_source_tab_v3.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ensureRid_${TS}"
echo "[BACKUP] ${F}.bak_ensureRid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_data_source_tab_v3.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P2_DS_ENSURE_RID_LATEST_SAFE_V1" in s:
    print("[OK] already patched ENSURE_RID")
    raise SystemExit(0)

# 1) add async ensure rid function (append near __vspDsApplyQueryFromUrl helper if exists)
anchor = "function __vspDsApplyQueryFromUrl(){"
idx = s.find(anchor)
if idx < 0:
    raise SystemExit("[ERR] missing __vspDsApplyQueryFromUrl (run v3_hook first?)")

inject = r'''
/* ===== VSP_P2_DS_ENSURE_RID_LATEST_SAFE_V1 ===== */
async function __vspDsEnsureRidLatestSafe(){
  try{
    if (state && state.rid) return true;

    // If URL has rid=..., use it
    try{
      const sp = new URL(window.location.href).searchParams;
      const ridq = String(sp.get("rid")||"").trim();
      if (ridq){
        state.rid = ridq;
        try{ const ridbox = document.querySelector('input[name="rid"], input#rid, input[data-testid="rid"], input[placeholder*="RID"]'); if(ridbox) ridbox.value = ridq; }catch(_){}
        return true;
      }
    }catch(_){}

    const url = "/api/vsp/rid_latest";
    for (let i=1;i<=4;i++){
      try{
        const ctl = new AbortController();
        const to = setTimeout(()=>{ try{ ctl.abort(); }catch(_){} }, 6000 + i*1500);
        const r = await fetch(url, {signal: ctl.signal, credentials:"same-origin", cache:"no-store"});
        clearTimeout(to);
        if (!r.ok) throw new Error("rid_latest http "+r.status);
        const j = await r.json();
        const rid = String((j && (j.rid||j.run_id||j.id)) || "").trim();
        if (rid){
          state.rid = rid;
          try{ const ridbox = document.querySelector('input[name="rid"], input#rid, input[data-testid="rid"], input[placeholder*="RID"]'); if(ridbox) ridbox.value = rid; }catch(_){}
          return true;
        }
      }catch(e){
        const msg = String(e && (e.name||e.message||e) || "");
        // AbortError/timeout => retry
        await new Promise(res=>setTimeout(res, 350*i));
      }
    }
  }catch(_){}
  return false;
}
try{ window.__vspDsEnsureRidLatestSafe = __vspDsEnsureRidLatestSafe; }catch(_){}
'''
# inject before __vspDsApplyQueryFromUrl
s = s[:idx] + inject + "\n" + s[idx:]

# 2) ensure init awaits rid before applyQueryFromUrl/loadFindings
old = 'await loadRunsPick();\n    try{ __vspDsApplyQueryFromUrl(); }catch(_){ }\n    await loadFindings();'
if old not in s:
    # fallback: find 'await loadRunsPick();' then 'await loadFindings();'
    m = re.search(r'await\s+loadRunsPick\(\)\s*;\s*([\s\S]{0,200})await\s+loadFindings\(\)\s*;', s)
    if not m:
        raise SystemExit("[ERR] cannot locate init loadRunsPick/loadFindings block")
    # replace first occurrence in that region
    s = s.replace('await loadRunsPick();', 'await loadRunsPick();\n    try{ await __vspDsEnsureRidLatestSafe(); }catch(_){ }', 1)
    s = s.replace('await loadFindings();', 'try{ __vspDsApplyQueryFromUrl(); }catch(_){ }\n    await loadFindings();', 1)
else:
    s = s.replace(old,
                  'await loadRunsPick();\n    try{ await __vspDsEnsureRidLatestSafe(); }catch(_){ }\n    try{ __vspDsApplyQueryFromUrl(); }catch(_){ }\n    await loadFindings();',
                  1)

p.write_text(s, encoding="utf-8")
print("[OK] patched ENSURE_RID + init await rid_latest")
PY

echo "[OK] patched. Now hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/data_source?severity=MEDIUM"
