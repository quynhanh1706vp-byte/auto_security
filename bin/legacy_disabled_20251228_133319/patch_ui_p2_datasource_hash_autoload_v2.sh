#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_hash_autoload_${TS}"
echo "[BACKUP] $F.bak_hash_autoload_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_datasource_tab_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")
TAG = "// === VSP_P2_DS_HASH_AUTOLOAD_V2 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

patch = r'''
// === VSP_P2_DS_HASH_AUTOLOAD_V2 ===
// Support router hash format: #datasource&sev=HIGH&tool=gitleaks&limit=200
// Auto-load when entering datasource tab, and always resolve RID from runs_index if missing.
(function(){
  function esc(s){ try{ return String(s); }catch(_){ return ""; } }

  function parseHash(){
    // accepts:
    //  - #datasource
    //  - #datasource&sev=HIGH&tool=gitleaks
    //  - #tab=datasource&sev=HIGH...
    let h = (location.hash || "").replace(/^#\/?/,"").trim();
    if (!h) return {tab:"dashboard", params:{}};

    // normalize: if starts with "tab="
    if (h.startsWith("tab=")){
      const sp = new URLSearchParams(h);
      const tab = sp.get("tab") || "";
      const params = {};
      sp.forEach((v,k)=>{ if(k!=="tab") params[k]=v; });
      return {tab, params};
    }

    // normalize: first token is tab name
    const parts = h.split("&");
    const tab = parts[0] || "";
    const params = {};
    for (let i=1;i<parts.length;i++){
      const part = parts[i];
      if (!part) continue;
      const kv = part.split("=",2);
      const k = decodeURIComponent(kv[0]||"");
      const v = decodeURIComponent(kv[1]||"");
      if (k) params[k]=v;
    }
    return {tab, params};
  }

  async function resolveLatestRID(){
    try{
      const r = await fetch("/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1", {cache:"no-store"});
      const j = await r.json();
      const rid = j?.items?.[0]?.run_id || "";
      return rid;
    }catch(_){
      return "";
    }
  }

  async function applyFromHash(){
    const x = parseHash();
    if ((x.tab||"").toLowerCase() !== "datasource") return;

    const sink = window.VSP_DATASOURCE_APPLY_FILTERS_V1;
    if (typeof sink !== "function") return;

    const f = Object.assign({limit:"200"}, x.params || {});
    // ensure rid
    if (!f.rid){
      const rid = await resolveLatestRID();
      if (rid) f.rid = rid;
    }

    try{
      await sink(f, {noHashSync:true});
    }catch(e){
      console.warn("[VSP_DS_HASH_AUTOLOAD_V2] sink failed:", e);
    }
  }

  // Patch drill router compatibility: if someone sets #tab=datasource..., convert to #datasource&...
  function normalizeHashIfNeeded(){
    const h = (location.hash || "");
    if (h.startsWith("#tab=datasource")){
      try{
        const sp = new URLSearchParams(h.replace(/^#/, ""));
        sp.delete("tab");
        const qs = sp.toString();
        const nh = "#datasource" + (qs ? ("&"+qs) : "");
        if (location.hash !== nh) history.replaceState(null, "", nh);
      }catch(_){}
    }
  }

  async function onHash(){
    normalizeHashIfNeeded();
    await applyFromHash();
  }

  window.addEventListener("hashchange", onHash);

  if (document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", onHash);
  }else{
    onHash();
  }
})();
'''
t = t.rstrip() + "\n\n" + patch + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended hash-autoload V2")
PY

node --check static/js/vsp_datasource_tab_v1.js >/dev/null
echo "[OK] node --check OK"
echo "[DONE] datasource hash/autoload patched. Restart + hard refresh."
