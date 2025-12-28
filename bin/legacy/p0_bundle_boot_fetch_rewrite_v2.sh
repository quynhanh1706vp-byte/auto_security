#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_bootrw_${TS}"
echo "[BACKUP] ${B}.bak_bootrw_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V2"
if marker in s:
    print("[SKIP] already injected")
    raise SystemExit(0)

inj = r"""
/* VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V2
   Purpose: ensure Dashboard can always resolve latest RID even when /api/vsp/rid_latest is degraded.
   - Rewrite fetch URLs containing: /api/vsp/latest_rid, /api/vsp/rid_latest, /api/vsp/*latest*
     to /api/vsp/rid_latest_gate_root
   - Bootstrap RID into localStorage + dispatch event vsp:rid
*/
(()=> {
  try{
    if (window.__vsp_p0_bundle_boot_fetch_rewrite_v2) return;
    window.__vsp_p0_bundle_boot_fetch_rewrite_v2 = true;

    const CANON = "/api/vsp/rid_latest_gate_root";
    const REWRITE_PAT = /\/api\/vsp\/(latest_rid|rid_latest)(\b|[^a-zA-Z0-9_])|\/api\/vsp\/[^"']*latest[^"']*/i;

    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch){
      window.fetch = async (input, init) => {
        try{
          let url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && REWRITE_PAT.test(url)) {
            // keep absolute origin if present
            const u = new URL(url, location.origin);
            u.pathname = CANON;
            u.search = "";
            const out = u.toString();
            return _fetch(out, init);
          }
        }catch(e){}
        return _fetch(input, init);
      };
    }

    async function bootstrapRid(){
      try{
        const r = await _fetch(CANON, {cache:"no-store"});
        if (!r.ok) return;
        const j = await r.json().catch(()=>null);
        const rid = (j && (j.rid || j.run_id)) ? (j.rid || j.run_id) : "";
        if (!rid) return;

        // store several keys (bundle/gatestory variants)
        try{
          localStorage.setItem("vsp_last_good_rid_v1", rid);
          localStorage.setItem("vsp_rid", rid);
          localStorage.setItem("vsp_last_rid", rid);
        }catch(e){}

        // broadcast event many modules already use
        try{
          window.dispatchEvent(new CustomEvent("vsp:rid", { detail: { rid } }));
        }catch(e){}

        // also set a global hint
        window.__vsp_rid = rid;
        console.log("[VSP][P0] bootstrap rid=", rid);
      }catch(e){}
    }

    // kick bootstrap quickly, then again after 1s (race-safe)
    bootstrapRid();
    setTimeout(bootstrapRid, 1000);
  }catch(e){}
})();
"""

# Put injection at the very top (before any code executes)
p.write_text(inj + "\n" + s, encoding="utf-8")
print("[OK] injected boot+fetch rewrite into bundle")
PY

echo "== smoke: bundle has marker =="
grep -n "VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V2" "$B" | head -n 2 || true

echo "== smoke: rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 220; echo

echo "[DONE] Ctrl+Shift+R (hard reload) /vsp5"
