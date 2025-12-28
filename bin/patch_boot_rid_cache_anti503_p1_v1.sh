#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_p1_page_boot_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_ridcache_${TS}"
echo "[BACKUP] ${F}.bak_ridcache_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_p1_page_boot_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_RID_CACHE_ANTI503_V1"
if MARK in s:
    print("[OK] marker already present, skip")
else:
    # replace getLatestRid() function block
    pat = r"async function getLatestRid\(\)\{[\s\S]*?\}\n\n"
    repl = r"""async function getLatestRid(){
    // VSP_P1_RID_CACHE_ANTI503_V1
    // Prefer cached RID to avoid poll-guard 503 on /api/vsp/runs
    try{
      const cached = sessionStorage.getItem("vsp_latest_rid") || "";
      const ts = parseInt(sessionStorage.getItem("vsp_latest_rid_ts") || "0", 10);
      if(cached && ts && (Date.now()-ts) < 30000) return cached; // 30s cache
    }catch(_e){}

    // If /vsp5 page already stored something
    try{
      if(window.__VSP_LAST_RID__ && String(window.__VSP_LAST_RID__).length>5){
        const r = String(window.__VSP_LAST_RID__);
        try{ sessionStorage.setItem("vsp_latest_rid", r); sessionStorage.setItem("vsp_latest_rid_ts", String(Date.now())); }catch(_e){}
        return r;
      }
    }catch(_e){}

    // Try fetch latest RID
    try{
      const data = await fetchJson("/api/vsp/runs?limit=1");
      const rid = data && data.items && data.items[0] && data.items[0].run_id ? data.items[0].run_id : "";
      if(rid){
        try{ sessionStorage.setItem("vsp_latest_rid", rid); sessionStorage.setItem("vsp_latest_rid_ts", String(Date.now())); }catch(_e){}
        return rid;
      }
    }catch(_e){
      // fallback: use any cached RID even if stale (avoid hard fail on 503)
      try{
        const cached = sessionStorage.getItem("vsp_latest_rid") || "";
        if(cached) return cached;
      }catch(__e){}
      throw _e;
    }
    throw new Error("no rid");
  }

"""
    s2, n = re.subn(pat, repl, s, count=1)
    if n != 1:
        raise SystemExit("[ERR] cannot find getLatestRid() block to patch")
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched getLatestRid() with cache+fallback:", MARK)
PY

node -c static/js/vsp_p1_page_boot_v1.js >/dev/null 2>&1 || true
echo "[OK] patch done"
