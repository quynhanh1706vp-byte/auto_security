#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# --- locate bundle JS (preferred) ---
BUNDLE="$(python3 - <<'PY'
from pathlib import Path
cands = []
p = Path("static/js")
if p.exists():
    for x in p.glob("*.js"):
        n = x.name.lower()
        if "bundle" in n and "commercial" in n:
            cands.append(x)
if not cands and p.exists():
    for x in p.glob("*.js"):
        n = x.name.lower()
        if "bundle" in n:
            cands.append(x)
cands = sorted(cands, key=lambda z: z.name)
print(str(cands[0]) if cands else "")
PY
)"
[ -n "$BUNDLE" ] || { echo "[ERR] cannot find bundle js under static/js"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] bundle not found: $BUNDLE"; exit 2; }
echo "[INFO] BUNDLE=$BUNDLE"
cp -f "$BUNDLE" "${BUNDLE}.bak_rule_autorefresh_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_rule_autorefresh_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, os

bundle = Path(os.environ["BUNDLE"])
s = bundle.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1"
if marker in s:
    print("[OK] bundle already has marker, skip.")
    raise SystemExit(0)

patch = r"""
/* VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1 (auto refresh Runs + DataSource after Apply Rule Overrides) */
(()=> {
  try{
    if (window.__vsp_p1_rule_overrides_autorefresh_v1) return;
    window.__vsp_p1_rule_overrides_autorefresh_v1 = true;

    const EVT = "vsp:rule_overrides_applied";
    const isRuleUrl = (u)=> {
      u = String(u||"");
      return /\/api\/ui\/rule_overrides/i.test(u) || /\/api\/vsp\/rule_overrides/i.test(u);
    };

    function safeReload(){
      try{ location.reload(); }catch(_){}
    }

    function afterApply(detail){
      try{
        const path = (location && location.pathname) ? String(location.pathname) : "";
        // Prefer calling known refresh hooks if present
        if (typeof window.refreshRuns === "function") { try{ window.refreshRuns(); }catch(_){ safeReload(); } return; }
        if (typeof window.refreshCounts === "function") { try{ window.refreshCounts(); }catch(_){ /* ignore */ } }

        // Data source pagination hook (we patch it to expose __vsp_ds_reload_v1)
        if (typeof window.__vsp_ds_reload_v1 === "function") { try{ window.__vsp_ds_reload_v1(); }catch(_){ /* fallback below */ } }

        // last resort: reload page if on runs/data_source
        if (/\/runs\b/i.test(path) || /\/data_source\b/i.test(path)) safeReload();
      }catch(_){}
    }

    window.addEventListener(EVT, (e)=> {
      afterApply((e && e.detail) || {});
    });

    // Wrap fetch once: detect successful Apply calls then dispatch event
    const origFetch = window.fetch;
    if (typeof origFetch === "function" && !origFetch.__vsp_p1_rule_overrides_autorefresh_v1){
      window.fetch = async function(input, init){
        const url = (typeof input === "string") ? input : (input && input.url) || "";
        const method = (init && init.method) ? String(init.method).toUpperCase() : "GET";

        const resp = await origFetch(input, init);

        try{
          if (url && isRuleUrl(url) && method !== "GET"){
            const clone = resp.clone();
            let j = null;
            try{ j = await clone.json(); }catch(_){ j = null; }

            const ok = !!(j && (j.ok === True || j.ok === true || j.status === "ok" || j.result === "ok"));
            if (resp.ok && ok){
              const detail = { url, method, ts: Date.now(), payload: j };
              try{ window.dispatchEvent(new CustomEvent(EVT, { detail })); }catch(_){}
              // also run locally immediately
              setTimeout(()=> afterApply(detail), 30);
            }
          }
        }catch(_){}

        return resp;
      };
      window.fetch.__vsp_p1_rule_overrides_autorefresh_v1 = true;
    }
  }catch(e){
    console && console.warn && console.warn("VSP_P1_RULE_OVERRIDES_AUTOREFRESH_V1 failed:", e);
  }
})();
"""

if not s.endswith("\n"):
    s += "\n"
s += "\n" + patch + "\n"
bundle.write_text(s, encoding="utf-8")
print("[OK] appended:", marker)
PY
BUNDLE="$BUNDLE"

# --- patch Data Source pagination JS to expose reload + listen to apply event ---
DSJS="static/js/vsp_data_source_pagination_v1.js"
if [ -f "$DSJS" ]; then
  cp -f "$DSJS" "${DSJS}.bak_listen_${TS}"
  echo "[BACKUP] ${DSJS}.bak_listen_${TS}"

  python3 - <<'PY'
from pathlib import Path
import os, re

p = Path("static/js/vsp_data_source_pagination_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_DS_LISTEN_RULE_APPLY_V1"
if marker in s:
    print("[OK] DS pagination already patched, skip.")
    raise SystemExit(0)

# We add: expose __vsp_ds_reload_v1 and listen event vsp:rule_overrides_applied to reload page 0.
addon = r"""
/* VSP_P1_DS_LISTEN_RULE_APPLY_V1 (listen apply event + expose reload) */
(()=> {
  try{
    const EVT = "vsp:rule_overrides_applied";
    // Expose reload hook used by bundle
    window.__vsp_ds_reload_v1 = ()=>{
      try{
        // prefer reset to 0 so user sees new counts quickly
        const st = window.__vsp_ds_page_v1 || { offset: 0, limit: 200 };
        const off = 0;
        // try call internal loadPage if we can find it (we can't directly), so just click Load after setting offset=0
        // easiest: trigger the Load button if present
        const btn = document.getElementById("VSP_DS_LOAD");
        if (btn){ btn.click(); return; }
        // fallback: hard reload if needed
        if (location && /\/data_source\b/i.test(location.pathname||"")) location.reload();
      }catch(_){}
    };

    window.addEventListener(EVT, ()=> {
      try{
        if (location && /\/data_source\b/i.test(location.pathname||"")){
          // reset offset to 0 by reloading (fast + safe)
          location.reload();
        }
      }catch(_){}
    });
  }catch(_){}
})();
"""
if not s.endswith("\n"):
    s += "\n"
s += "\n" + addon + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended:", marker)
PY
else
  echo "[WARN] DS pagination js not found (skip listen patch): $DSJS"
fi

echo "[OK] autorefresh patch applied."
echo "[NEXT] restart UI + hard refresh (Ctrl+F5). Then Apply Rule Overrides and watch /runs + /data_source refresh automatically."
