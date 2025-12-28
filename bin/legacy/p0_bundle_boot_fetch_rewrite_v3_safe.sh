#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$B" "${B}.bak_bootrw_v3_${TS}"
echo "[BACKUP] ${B}.bak_bootrw_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) Remove previous V2 block if exists (it was injected at top)
m = "/* VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V2"
i = s.find(m)
if i != -1:
    j = s.find("})();", i)
    if j != -1:
        j2 = j + len("})();")
        # also trim following newlines
        while j2 < len(s) and s[j2] in "\r\n":
            j2 += 1
        s = s[:i] + s[j2:]
        print("[OK] removed V2 injection block")
    else:
        print("[WARN] V2 marker found but cannot locate end; keeping file")

marker_v3 = "VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V3"
if marker_v3 in s:
    print("[SKIP] V3 already injected")
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

inj = r"""
/* VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V3
   IMPORTANT: do NOT rewrite /api/vsp/rid_latest (it returns KPI counts_total payload).
   - Bootstrap RID+gate_root from /api/vsp/rid_latest_gate_root
   - Rewrite ONLY /api/vsp/latest_rid* (fetch + XHR) -> /api/vsp/rid_latest_gate_root
*/
(()=> {
  try{
    if (window.__vsp_p0_bundle_boot_fetch_rewrite_v3) return;
    window.__vsp_p0_bundle_boot_fetch_rewrite_v3 = true;

    const CANON = "/api/vsp/rid_latest_gate_root";
    const REWRITE_PAT = /\/api\/vsp\/latest_rid\b|\/api\/vsp\/latest_rid_/i; // NOT rid_latest

    const toCanon = (url) => {
      try{
        const u = new URL(url, location.origin);
        u.pathname = CANON;
        u.search = "";
        return u.toString();
      }catch(e){
        return CANON;
      }
    };

    // fetch hook
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (_fetch){
      window.fetch = async (input, init) => {
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && REWRITE_PAT.test(url)) return _fetch(toCanon(url), init);
        }catch(e){}
        return _fetch(input, init);
      };
    }

    // XHR hook (axios / old code)
    const _open = XMLHttpRequest && XMLHttpRequest.prototype && XMLHttpRequest.prototype.open;
    if (_open){
      XMLHttpRequest.prototype.open = function(method, url){
        try{
          if (url && typeof url === "string" && REWRITE_PAT.test(url)) {
            url = toCanon(url);
          }
        }catch(e){}
        return _open.apply(this, [method, url, ...[].slice.call(arguments, 2)]);
      };
    }

    async function bootstrap(){
      if (!_fetch) return;
      try{
        const r = await _fetch(CANON, {cache:"no-store"});
        if (!r.ok) return;
        const j = await r.json().catch(()=>null);
        const rid = j && (j.rid || j.run_id) ? (j.rid || j.run_id) : "";
        const gate_root = j && j.gate_root ? j.gate_root : "";
        if (!rid) return;

        const keys = [
          "vsp_rid","vsp_last_rid","vsp_last_good_rid_v1",
          "vsp5_rid","vsp5.rid","VSP_RID","VSP_LAST_RID",
        ];
        try{ keys.forEach(k=>localStorage.setItem(k, rid)); }catch(e){}
        if (gate_root){
          const gkeys = ["vsp_gate_root","vsp5_gate_root","VSP_GATE_ROOT"];
          try{ gkeys.forEach(k=>localStorage.setItem(k, gate_root)); }catch(e){}
        }

        window.__vsp_rid = rid;
        window.__vsp_gate_root = gate_root || null;

        try{ window.dispatchEvent(new CustomEvent("vsp:rid", {detail:{rid, gate_root}})); }catch(e){}
        try{ window.dispatchEvent(new CustomEvent("vsp:gate_root", {detail:{rid, gate_root}})); }catch(e){}

        console.log("[VSP][P0] boot rid=", rid, "gate_root=", gate_root || "(none)");
      }catch(e){}
    }

    bootstrap();
    setTimeout(bootstrap, 800);
  }catch(e){}
})();
"""

p.write_text(inj + "\n" + s, encoding="utf-8")
print("[OK] injected V3 (no rid_latest rewrite)")
PY

echo "== smoke: bundle markers =="
grep -n "VSP_P0_BUNDLE_BOOT_FETCH_REWRITE_V3" "$B" | head -n 2 || true

echo "== smoke: rid_latest must still be KPI payload (no rid key is OK) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 200; echo

echo "== smoke: rid_latest_gate_root must have rid =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 200; echo

echo "[DONE] Ctrl+Shift+R /vsp5"
