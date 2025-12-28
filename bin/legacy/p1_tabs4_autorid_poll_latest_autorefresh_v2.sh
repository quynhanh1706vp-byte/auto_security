#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
TS="$(date +%Y%m%d_%H%M%S)"

A="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$A" ] || { echo "[ERR] missing $A"; exit 2; }

cp -f "$A" "${A}.bak_poll_${TS}"
echo "[BACKUP] ${A}.bak_poll_${TS}"

node - <<'NODE'
const fs = require("fs");
const A="static/js/vsp_tabs4_autorid_v1.js";
let s = fs.readFileSync(A,"utf8");

const MARK="VSP_P1_TABS4_AUTORID_POLL_LATEST_AUTOREFRESH_V2";
if(s.includes(MARK)){
  console.log("[OK] already patched:", MARK);
  process.exit(0);
}

const inject = `
/* ${MARK}
 * - Poll /api/vsp/rid_latest_gate_root_v2 periodically
 * - If RID changes: store to localStorage + dispatch VSP_RID_CHANGED
 * - Auto refresh only for 4 tabs (NO /vsp5 dashboard)
 * - Safe fallback: location.reload() if no reload function exists
 */
(()=> {
  try {
    const RID_API = "/api/vsp/rid_latest_gate_root_v2";
    const KEY = "VSP_RID_CURRENT";
    const POLL_MS = 12000; // commercial default 12s
    const PATHS = new Set(["/runs","/runs_reports","/settings","/data_source","/rule_overrides"]);
    const isTabs4 = () => {
      try {
        const p = (location.pathname || "/").replace(/\\/$/,"") || "/";
        if (p.startsWith("/vsp5")) return false;
        return PATHS.has(p);
      } catch(e){ return false; }
    };

    const toast = (msg) => {
      try {
        let el = document.getElementById("vspTabs4ToastV2");
        if(!el){
          el = document.createElement("div");
          el.id = "vspTabs4ToastV2";
          el.style.cssText = "position:fixed;right:14px;bottom:14px;z-index:99999;background:rgba(10,18,32,0.92);border:1px solid rgba(255,255,255,0.12);color:#e7eefc;padding:10px 12px;border-radius:12px;font:12px/1.35 system-ui;max-width:360px;box-shadow:0 14px 40px rgba(0,0,0,0.45)";
          document.body.appendChild(el);
        }
        el.textContent = msg;
        el.style.display = "block";
        clearTimeout(window.__vspTabs4ToastT);
        window.__vspTabs4ToastT = setTimeout(()=>{ try{ el.style.display="none"; }catch(e){} }, 2600);
      } catch(e){}
    };

    const getCur = () => {
      try { return localStorage.getItem(KEY) || ""; } catch(e){ return ""; }
    };

    const setCur = (rid) => {
      try { localStorage.setItem(KEY, String(rid||"")); } catch(e){}
    };

    const emit = (rid, prev) => {
      try {
        window.dispatchEvent(new CustomEvent("VSP_RID_CHANGED", { detail: { rid, prev, ts: Date.now(), via: "poll_v2" }}));
      } catch(e){}
    };

    const callReloadOrFallback = (detail) => {
      if(!isTabs4()) return;

      const p = (location.pathname || "/").replace(/\\/$/,"") || "/";
      // never touch dashboard
      if(p.startsWith("/vsp5")) return;

      const tryCall = (fnName) => {
        try {
          const f = window[fnName];
          if(typeof f === "function"){
            f(detail||{});
            return true;
          }
        } catch(e){}
        return false;
      };

      // prefer real reload functions if available
      let ok = false;
      if(p === "/runs" || p === "/runs_reports"){
        ok = tryCall("VSP_reloadRuns");
      } else if(p === "/data_source"){
        ok = tryCall("VSP_reloadDataSource");
      } else if(p === "/settings"){
        ok = tryCall("VSP_reloadSettings");
      } else if(p === "/rule_overrides"){
        // safety: avoid nuking unsaved edits if page exposes a dirty flag
        try {
          if(window.__VSP_RULE_OVERRIDES_DIRTY) {
            toast("RID changed → not auto-reloading Rule Overrides (unsaved edits).");
            return;
          }
        } catch(e){}
        ok = tryCall("VSP_reloadRuleOverrides");
      }

      if(ok){
        toast("RID changed → refreshed data");
        return;
      }

      // fallback: soft reload this tab (commercial-safe)
      toast("RID changed → reloading tab to get latest results…");
      try {
        // throttle to avoid reload storm
        const now = Date.now();
        const last = window.__vspTabs4LastReloadTs || 0;
        if(now - last < 8000) return;
        window.__vspTabs4LastReloadTs = now;
        location.reload();
      } catch(e){}
    };

    async function pollOnce(){
      if(!isTabs4()) return;
      try {
        const r = await fetch(RID_API, { cache: "no-store" });
        const j = await r.json();
        const rid = (j && j.ok && j.rid) ? String(j.rid) : "";
        if(!rid) return;

        const prev = getCur();
        if(rid && rid !== prev){
          setCur(rid);
          emit(rid, prev);
          callReloadOrFallback({ rid, prev });
        }
      } catch(e){}
    }

    // Listen to RID changes from other sources too
    try {
      window.addEventListener("VSP_RID_CHANGED", (ev)=>{
        try {
          const d = ev && ev.detail ? ev.detail : {};
          // only react if we're on tabs4
          if(isTabs4()){
            // don't double reload: ignore if via poll already handled
            if(d && d.via === "poll_v2") return;
            callReloadOrFallback(d);
          }
        } catch(e){}
      });
    } catch(e){}

    // Start poll loop (only if tabs4)
    if(isTabs4()){
      setTimeout(pollOnce, 600);
      setInterval(pollOnce, POLL_MS);
    }
  } catch(e){}
})();
`;

s += "\n\n" + inject + "\n";
fs.writeFileSync(A, s);
console.log("[OK] patched autorid with polling + autorefresh:", MARK);
NODE

node --check static/js/vsp_tabs4_autorid_v1.js
echo "[OK] node --check passed for autorid"
