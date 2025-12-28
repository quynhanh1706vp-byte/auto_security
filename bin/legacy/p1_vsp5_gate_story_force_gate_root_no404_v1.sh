#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need find; need grep

TS="$(date +%Y%m%d_%H%M%S)"

# find gate story JS files (cover different naming)
mapfile -t FILES < <(find static/js -maxdepth 1 -type f -name 'vsp_dashboard_gate*story*.js' -print 2>/dev/null | sort)
[ "${#FILES[@]}" -gt 0 ] || { echo "[ERR] cannot find static/js/vsp_dashboard_gate*story*.js"; exit 2; }

for f in "${FILES[@]}"; do
  cp -f "$f" "${f}.bak_force_gate_root_${TS}"
  echo "[BACKUP] ${f}.bak_force_gate_root_${TS}"
done

python3 - <<'PY'
from pathlib import Path
import textwrap

marker = "VSP_P1_GATE_ROOT_PROXY_V1"

proxy = textwrap.dedent(r"""
/* VSP_P1_GATE_ROOT_PROXY_V1
 * Fix commercial: prevent GateStory probing wrong RID first.
 * - Always wait for /api/vsp/runs and pick rid_latest_gate_root || rid_latest_gate || rid_latest
 * - Force /api/vsp/run_file_allow requests to:
 *     rid = rid_latest_gate_root
 *     path = run_gate_summary.json
 */
(()=> {
  try {
    if (window.__vsp_p1_gate_root_proxy_v1) return;
    window.__vsp_p1_gate_root_proxy_v1 = true;

    const ORIGIN = location.origin;
    const RUNS_URL = ORIGIN + "/api/vsp/runs?limit=10&_=" + Date.now();

    const pickRid = (j)=> {
      try {
        if (!j) return "";
        const rid = (j.rid_latest_gate_root || j.rid_latest_gate || j.rid_latest || "").toString().trim();
        if (!rid) return "";
        window.vsp_rid_latest = rid;
        try {
          localStorage.setItem("vsp_rid_latest_gate_root_v1", rid);
          localStorage.setItem("vsp_rid_latest_v1", rid);
        } catch(e){}
        return rid;
      } catch(e) { return ""; }
    };

    // single shared promise
    window.__vsp_gate_root_rid_promise = window.__vsp_gate_root_rid_promise || fetch(RUNS_URL, {cache:"no-store"})
      .then(r => r.json().catch(()=>null))
      .then(j => pickRid(j))
      .catch(()=> (localStorage.getItem("vsp_rid_latest_gate_root_v1")||localStorage.getItem("vsp_rid_latest_v1")||"").toString().trim());

    const origFetch = window.fetch.bind(window);

    window.fetch = function(input, init){
      try{
        const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        if (url0 && url0.indexOf("/api/vsp/run_file_allow") >= 0) {
          // delay until we have rid_latest_gate_root, then rewrite rid+path to safe values
          return window.__vsp_gate_root_rid_promise.then((rid)=>{
            try{
              const u = new URL(url0, ORIGIN);
              if (rid) u.searchParams.set("rid", rid);
              // force only root gate summary to avoid 404/403
              u.searchParams.set("path", "run_gate_summary.json");
              const url1 = u.toString();
              // keep Request object if any
              if (typeof input !== "string" && input && input.url) {
                const req = new Request(url1, input);
                return origFetch(req, init);
              }
              return origFetch(url1, init);
            } catch(e){
              return origFetch(input, init);
            }
          });
        }
      } catch(e){}
      return origFetch(input, init);
    };

    console.log("[GateStoryV1][%s] installed", "VSP_P1_GATE_ROOT_PROXY_V1");
  } catch(e){}
})();
""").strip() + "\n\n"

for fp in Path("static/js").glob("vsp_dashboard_gate*story*.js"):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[SKIP] already patched:", fp)
        continue
    fp.write_text(proxy + s, encoding="utf-8")
    print("[OK] patched:", fp)
PY

echo "== verify marker =="
grep -RIn --exclude='*.bak_*' "VSP_P1_GATE_ROOT_PROXY_V1" static/js/vsp_dashboard_gate*story*.js | head -n 20 || true

echo
echo "DONE. Now do: Ctrl+F5 on /vsp5 (or open Incognito)."
echo "Expected: no more 404/403 from /api/vsp/run_file_allow; console shows GateStoryV1 installed VSP_P1_GATE_ROOT_PROXY_V1."
