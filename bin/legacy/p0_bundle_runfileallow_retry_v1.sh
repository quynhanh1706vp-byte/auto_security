#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
node_ok=0; command -v node >/dev/null 2>&1 && node_ok=1

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_runfileallow_retry_${TS}"
echo "[BACKUP] ${B}.bak_runfileallow_retry_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RUNFILEALLOW_RETRY_V1"
if marker in s:
    print("[SKIP] already has", marker)
    sys.exit(0)

inj = r"""/* VSP_P0_RUNFILEALLOW_RETRY_V1 (alias rid_latest + retry run_file_allow with rid/gate_root variants) */
(()=> {
  if (window.__vsp_p0_runfileallow_retry_v1) return;
  window.__vsp_p0_runfileallow_retry_v1 = true;

  const _origFetch = window.fetch ? window.fetch.bind(window) : null;
  if (!_origFetch) return;

  const _latestMetaCache = { t: 0, v: null };

  function _now(){ return Date.now(); }
  function _sleep(ms){ return new Promise(r => setTimeout(r, ms)); }

  async function _getLatestMeta(){
    const age = _now() - (_latestMetaCache.t || 0);
    if (_latestMetaCache.v && age < 1500) return _latestMetaCache.v; // cache ~1.5s
    const urls = [
      "/api/vsp/rid_latest_gate_root",
      "/api/vsp/latest_rid"
    ];
    for (const u of urls){
      try{
        const r = await _origFetch(u, { cache: "no-store" });
        const ct = (r.headers.get("content-type") || "").toLowerCase();
        if (!r.ok) continue;
        const txt = await r.text();
        const t = txt.trim();
        if (!(t.startsWith("{") || t.startsWith("["))) continue;
        const j = JSON.parse(t);
        if (j && (j.ok === true) && (j.rid || j.run_id || j.gate_root || j.gate_root_id)){
          _latestMetaCache.t = _now();
          _latestMetaCache.v = j;
          return j;
        }
      }catch(e){}
    }
    return null;
  }

  function _normRid(rid){
    if (!rid) return rid;
    let r = String(rid).trim();
    // common variants seen in your env
    r = r.replace("VSP_CI_RUN_", "VSP_CI_");
    r = r.replace("_CI_RUN_", "_CI_");
    r = r.replace("_RUN_", "_");
    return r;
  }

  function _buildRunFileAllowCandidates(urlStr, meta){
    const u = new URL(urlStr, location.origin);
    const path = u.searchParams.get("path") || "";
    const rid0 = u.searchParams.get("rid") || "";
    const cand = [];

    function addRid(v){
      if (!v) return;
      const uu = new URL(u.toString());
      uu.searchParams.set("rid", v);
      cand.push(uu.toString());
    }

    addRid(rid0);
    addRid(_normRid(rid0));

    if (meta){
      const ridm = meta.rid || meta.run_id || "";
      const gr   = meta.gate_root || meta.gate_root_id || meta.gate_rootId || "";
      addRid(ridm);
      addRid(_normRid(ridm));
      addRid(gr);
      // sometimes UI shows gate_root without prefix; try also prefixed
      if (gr && !String(gr).startsWith("gate_root_")) addRid("gate_root_" + gr);
      // sometimes rid is actually gate_root-like
      if (ridm && String(ridm).startsWith("gate_root_")) addRid(String(ridm).replace(/^gate_root_/, ""));
    }

    // de-dupe
    const out = [];
    const seen = new Set();
    for (const x of cand){
      if (!seen.has(x)){
        seen.add(x);
        out.push(x);
      }
    }

    // last resort: if we have meta.gate_root_id but original url path missing -> keep it anyway
    return { path, urls: out };
  }

  async function _fetchPreferJson(urls, init){
    let lastResp = null;
    for (const u of urls){
      try{
        const r = await _origFetch(u, init);
        lastResp = r;
        const ct = (r.headers.get("content-type") || "").toLowerCase();
        if (r.ok && (ct.includes("application/json") || ct.includes("+json"))) return r;

        // header may be wrong; peek body
        const t = (await r.clone().text()).trim();
        if (r.ok && (t.startsWith("{") || t.startsWith("["))){
          return new Response(t, { status: 200, headers: { "content-type": "application/json" } });
        }
      }catch(e){
        continue;
      }
    }
    return lastResp || _origFetch(urls[0], init);
  }

  window.fetch = async function(input, init){
    try{
      const url = (typeof input === "string") ? input : (input && input.url ? input.url : "");
      if (!url) return _origFetch(input, init);

      // alias: never rely on degraded demoapp rid_latest
      if (url.includes("/api/vsp/rid_latest") && !url.includes("rid_latest_gate_root")){
        const u = url.replace("/api/vsp/rid_latest", "/api/vsp/rid_latest_gate_root");
        return _origFetch(u, init);
      }

      // retry resolver for run_file_allow
      if (url.includes("/api/vsp/run_file_allow")){
        const meta = await _getLatestMeta();
        const built = _buildRunFileAllowCandidates(url, meta);
        if (built.urls.length > 1){
          return _fetchPreferJson(built.urls, init);
        }
        return _origFetch(input, init);
      }

      return _origFetch(input, init);
    }catch(e){
      return _origFetch(input, init);
    }
  };
})();
"""
p.write_text(inj + "\n" + s, encoding="utf-8")
print("[OK] injected:", marker)
PY

if [ "$node_ok" = "1" ]; then
  node --check "$B" >/dev/null && echo "[OK] node syntax OK"
else
  echo "[WARN] node not found; skip syntax check"
fi

echo "[DONE] Hard reload: Ctrl+Shift+R on /vsp5"
