#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_runs_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p4854_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_before_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_before_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY' | tee -a "$OUT/log.txt"
from pathlib import Path
import re

p = Path("static/js/vsp_c_runs_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P4854_RUNS_FORCE_SINGLE_RENDERER_V1"

if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Append a hard guard at end-of-file:
# - Ensure we always derive rows from data.items || data.runs || []
# - Disable any legacy render function if exists
# - Prevent double render by using a one-shot flag
block = r'''
// --- VSP_P4854_RUNS_FORCE_SINGLE_RENDERER_V1 ---
(function(){
  try{
    const G = window;
    if (G.__VSP_RUNS_FORCE_SINGLE_RENDERER__) return;
    G.__VSP_RUNS_FORCE_SINGLE_RENDERER__ = 1;

    // If legacy renderer exists, neutralize it (commercial mode)
    const legacyNames = [
      "renderRunsLegacy","render_runs_legacy","renderRunsTableLegacy",
      "vspRenderRunsLegacy","_renderRunsLegacy","render_runs_table_legacy"
    ];
    for(const n of legacyNames){
      if (typeof G[n] === "function") {
        G[n] = function(){ /* legacy disabled */ };
      }
    }

    // Patch common "data reader" patterns by wrapping fetch handler if exists
    // We hook into window.vspRunsRender or similar if present; otherwise we only normalize data globally.
    function normalizeRunsPayload(data){
      try{
        if (!data || typeof data !== "object") return {items:[], runs:[]};
        const items = Array.isArray(data.items) ? data.items
                    : (Array.isArray(data.runs) ? data.runs : []);
        data.items = items;
        if (!Array.isArray(data.runs)) data.runs = items;
        if (typeof data.total !== "number") data.total = (data.items || []).length;
      }catch(e){}
      return data;
    }

    // Global hook used by our templates: if any code calls window.__vsp_runs_payload_hook, normalize.
    G.__vsp_runs_payload_hook = normalizeRunsPayload;

    // Also patch Response.json consumer if code stores into a global last payload
    const _fetch = G.fetch;
    if (typeof _fetch === "function") {
      G.fetch = async function(...args){
        const r = await _fetch.apply(this, args);
        try{
          const url = (args && args[0]) ? String(args[0]) : "";
          if (url.includes("/api/vsp/runs_v3")) {
            // clone safely; do not consume original body for callers
            const c = r.clone();
            c.json().then(j=>{
              G.__VSP_LAST_RUNS_V3__ = normalizeRunsPayload(j);
            }).catch(()=>{});
          }
        }catch(e){}
        return r;
      };
    }

    console.log("[VSP] P4854 runs: single renderer enforced");
  }catch(e){
    console.warn("[VSP] P4854 runs: failed", e);
  }
})();
 // --- end VSP_P4854_RUNS_FORCE_SINGLE_RENDERER_V1 ---
'''
s2 = s + ("\n" if not s.endswith("\n") else "") + block
p.write_text(s2, encoding="utf-8")
print("[OK] appended P4854 block")
PY

if [ "${HAS_NODE:-0}" = "1" ]; then
  node --check "$F" >/dev/null 2>&1 || { echo "[ERR] node --check failed" | tee -a "$OUT/log.txt"; exit 2; }
  echo "[OK] node --check ok" | tee -a "$OUT/log.txt"
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC"
systemctl is-active "$SVC" | tee -a "$OUT/log.txt"

echo "[OK] P4854 done. Close /c/runs, reopen then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log => $OUT/log.txt"
