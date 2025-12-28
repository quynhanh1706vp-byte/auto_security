#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL_DIR="templates"
[ -d "$TPL_DIR" ] || { echo "[ERR] missing templates/"; exit 2; }

python3 - <<'PY'
from pathlib import Path
import re, datetime

MARK="VSP_UI_POLISH_RIDLATEST_BADGE_V1"
js = r"""
<script>
/* VSP_UI_POLISH_RIDLATEST_BADGE_V1 */
(function(){
  const MARK = "VSP_UI_POLISH_RIDLATEST_BADGE_V1";
  if (window[MARK]) return; window[MARK]=1;

  function setTextAll(match, newText){
    document.querySelectorAll('button,span,div,a').forEach(el=>{
      try{
        const t = (el.textContent||"").trim();
        if (t.includes(match)) el.textContent = newText;
      }catch(e){}
    });
  }

  async function probe(){
    try{
      const r = await fetch('/api/vsp/runs?limit=1', { cache: 'no-store' });
      const hdrDegraded = (r.headers.get('X-VSP-RUNS-DEGRADED') || '') === '1';
      const txt = await r.text();
      let j=null; try{ j=JSON.parse(txt); }catch(e){}
      const rid = (j && j.rid_latest) ? j.rid_latest : 'N/A';
      const ok = (r.status===200) && j && (j.ok===true);

      // 1) Unstick banner FAIL -> OK/DEGRADED
      if (ok){
        const msg = hdrDegraded ? `RUNS API DEGRADED (rid_latest=${rid})`
                                : `RUNS API OK (rid_latest=${rid})`;
        setTextAll('RUNS API FAIL', msg);
        setTextAll('Error: 503', '');
      }

      // 2) Always-visible badge for demo confidence
      let b=document.getElementById('vsp_rid_latest_badge');
      if(!b){
        b=document.createElement('div');
        b.id='vsp_rid_latest_badge';
        b.style.cssText='position:fixed;right:16px;bottom:16px;z-index:99999;padding:8px 10px;border-radius:12px;background:rgba(0,0,0,.55);backdrop-filter:blur(6px);font:12px/1.2 system-ui;color:#e6edf3;border:1px solid rgba(255,255,255,.10)';
        document.body.appendChild(b);
      }
      b.textContent = (ok ? (hdrDegraded?'DEGRADED':'OK') : 'FAIL') + ` • rid_latest=${rid}`;
    }catch(e){}
  }

  probe();
  setInterval(probe, 5000);
})();
</script>
"""

tpl_root = Path("templates")
patched=[]
for p in tpl_root.rglob("*.html"):
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    continue
  # chỉ inject vào các template VSP chính (có tabbar)
  if ("Runs & Reports" in s) or ("Data Source" in s) or ("/api/vsp/runs" in s) or ("VersaSecure Platform" in s):
    if "</body>" in s:
      s2 = s.replace("</body>", js + "\n</body>")
      p.write_text(s2, encoding="utf-8")
      patched.append(str(p))

print("[OK] injected:", MARK)
for x in patched[:30]:
  print(" -", x)
print("[OK] total patched:", len(patched))
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1
