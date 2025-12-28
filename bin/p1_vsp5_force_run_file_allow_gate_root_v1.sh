#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_force_runfile_gate_root_${TS}"
echo "[BACKUP] ${JS}.bak_force_runfile_gate_root_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_FORCE_RUNFILE_ALLOW_GATE_ROOT_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P0_FORCE_RUNFILE_ALLOW_GATE_ROOT_V1
   Force tool-truth at data plane:
   - Fetch /api/vsp/runs -> cache rid_latest_gate_root
   - Rewrite any /api/vsp/run_file_allow?rid=...&path=run_gate(_summary).json to use gate_root
*/
(()=> {
  try{
    if (window.__vsp_p0_force_runfile_gate_root_v1) return;
    window.__vsp_p0_force_runfile_gate_root_v1 = true;

    const KEY = "__vsp_gate_root_current_v1";
    async function initGateRoot(){
      try{
        const r = await fetch("/api/vsp/runs?_ts=" + Date.now(), { cache:"no-store" });
        if (!r.ok) return;
        const j = await r.json();
        const rid = (j && (j.rid_latest_gate_root || j.rid_latest || j.rid_last_good || j.rid_latest_findings)) || "";
        if (rid){
          window.__vsp_gate_root_current = rid;
          sessionStorage.setItem(KEY, rid);
          console.log("[VSP][gate_root] current:", rid);
        }
      }catch(e){}
    }

    // kick early
    initGateRoot();

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    if (window.__vsp_p0_runfile_fetch_wrapped_v1) return;
    window.__vsp_p0_runfile_fetch_wrapped_v1 = true;

    window.fetch = async (input, init) => {
      // get latest cached gate_root
      const gateRoot = (window.__vsp_gate_root_current || sessionStorage.getItem(KEY) || "").trim();

      // normalize URL string
      let url = "";
      try{
        url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      }catch(e){}

      // rewrite run_file_allow gate files to gate_root
      try{
        if (gateRoot && url && url.indexOf("/api/vsp/run_file_allow") !== -1 &&
            (url.indexOf("path=run_gate_summary.json") !== -1 || url.indexOf("path=run_gate.json") !== -1)) {

          const u = new URL(url, location.origin);
          const rid0 = u.searchParams.get("rid") || "";
          if (rid0 && rid0 !== gateRoot){
            u.searchParams.set("rid", gateRoot);
            const newUrl = u.toString();
            console.log("[VSP][run_file_allow_rewrite] rid:", rid0, "=>", gateRoot);
            input = (typeof input === "string") ? newUrl : new Request(newUrl, input);
          }
        }
      }catch(e){
        console.warn("[VSP][run_file_allow_rewrite] err", e);
      }

      const res = await _fetch(input, init);

      // also keep gate_root updated when /api/vsp/runs is fetched by anyone
      try{
        if (url && url.indexOf("/api/vsp/runs") !== -1 && res && res.ok && typeof res.json === "function"){
          const _json = res.json.bind(res);
          res.json = async () => {
            const j = await _json();
            try{
              const rid = (j && (j.rid_latest_gate_root || j.rid_latest || j.rid_last_good || j.rid_latest_findings)) || "";
              if (rid){
                window.__vsp_gate_root_current = rid;
                sessionStorage.setItem(KEY, rid);
              }
            }catch(e){}
            return j;
          };
        }
      }catch(e){}
      return res;
    };

    console.log("[VSP][runfile_gate_root] installed");
  }catch(e){
    console.warn("[VSP][runfile_gate_root] init failed", e);
  }
})();
"""

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended run_file_allow gate_root rewrite block")
PY

echo "== node --check =="
node --check static/js/vsp_dashboard_gate_story_v1.js
echo "[OK] syntax OK"
echo "[NEXT] Open /vsp5 and HARD reload (Ctrl+Shift+R)."
