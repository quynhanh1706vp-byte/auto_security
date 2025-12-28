#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_fetch_throttle_${TS}"
echo "[BACKUP] ${F}.bak_fetch_throttle_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_GATE_FETCH_THROTTLE_AND_GATE_ROOT_RID_V1"
if marker in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

block = textwrap.dedent(r"""
/* VSP_P1_GATE_FETCH_THROTTLE_AND_GATE_ROOT_RID_V1
 * - Throttle / cache repeated GET /api/vsp/run_file_allow (gate json) to stop DevTools spam
 * - If localStorage has vsp_rid_latest_gate_root_v1, rewrite rid=... for gate json requests to gate_root RID
 */
(()=> {
  try {
    if (window.__vsp_p1_gate_fetch_throttle_and_gate_root_rid_v1) return;
    window.__vsp_p1_gate_fetch_throttle_and_gate_root_rid_v1 = true;

    const ORIG_FETCH = window.fetch ? window.fetch.bind(window) : null;
    if (!ORIG_FETCH) return;

    const CACHE = new Map(); // key -> {ts, inflight, text, status, ct}
    const COOLDOWN_MS = 15000; // 15s cache window for SAME URL

    function isRunFileAllowUrl(u){
      return (typeof u === "string") && (u.indexOf("/api/vsp/run_file_allow") >= 0);
    }

    function wantsGateJson(urlObj){
      const path = (urlObj.searchParams.get("path")||"").toLowerCase();
      const name = (urlObj.searchParams.get("name")||"").toLowerCase();
      return path.endsWith("run_gate.json") or path.endsWith("run_gate_summary.json") or \
             name.endswith("run_gate.json") or name.endswith("run_gate_summary.json")
    }
  } catch(e) { /* noop */ }
})();
""").strip("\n")

# Python can't keep JS "or" - fix below by writing correct JS version
block = block.replace(" or ", " || ").replace(" or \\", " || ")

# Rebuild proper JS function wantsGateJson
block = re.sub(r'function wantsGateJson\([\s\S]*?\}\n\s*\}', '', block)

block = textwrap.dedent(r"""
/* VSP_P1_GATE_FETCH_THROTTLE_AND_GATE_ROOT_RID_V1
 * - Throttle / cache repeated GET /api/vsp/run_file_allow (gate json) to stop DevTools spam
 * - If localStorage has vsp_rid_latest_gate_root_v1, rewrite rid=... for gate json requests to gate_root RID
 */
(()=> {
  try {
    if (window.__vsp_p1_gate_fetch_throttle_and_gate_root_rid_v1) return;
    window.__vsp_p1_gate_fetch_throttle_and_gate_root_rid_v1 = true;

    const ORIG_FETCH = window.fetch ? window.fetch.bind(window) : null;
    if (!ORIG_FETCH) return;

    const CACHE = new Map(); // key -> {ts, inflight, text, status, ct}
    const COOLDOWN_MS = 15000; // 15s cache window for SAME URL

    function isRunFileAllowUrl(u){
      return (typeof u === "string") && (u.indexOf("/api/vsp/run_file_allow") >= 0);
    }

    function wantsGateJson(urlObj){
      const path = (urlObj.searchParams.get("path")||"").toLowerCase();
      const name = (urlObj.searchParams.get("name")||"").toLowerCase();
      return (
        path.endsWith("run_gate.json") ||
        path.endsWith("run_gate_summary.json") ||
        name.endsWith("run_gate.json") ||
        name.endsWith("run_gate_summary.json")
      );
    }

    function rewriteToGateRoot(u){
      try{
        const url = new URL(u, window.location.origin);
        if (url.pathname !== "/api/vsp/run_file_allow") return u;

        // only rewrite for gate json requests
        if (!wantsGateJson(url)) return u;

        const gateRid = (localStorage.getItem("vsp_rid_latest_gate_root_v1")||"").trim();
        if (!gateRid) return u;

        const rid = (url.searchParams.get("rid")||"").trim();
        if (!rid || rid !== gateRid) url.searchParams.set("rid", gateRid);

        return url.toString();
      } catch(e){
        return u;
      }
    }

    window.fetch = function(input, init){
      const raw = (typeof input === "string") ? input : (input && input.url ? input.url : String(input));
      const u = isRunFileAllowUrl(raw) ? rewriteToGateRoot(raw) : raw;
      const key = u;
      const now = Date.now();
      const ent = CACHE.get(key);

      // 1) inflight de-dupe
      if (ent && ent.inflight && (now - ent.ts) < COOLDOWN_MS) return ent.inflight;

      // 2) cached response (recreate Response from text)
      if (ent && ent.text && (now - ent.ts) < COOLDOWN_MS) {
        try{
          return Promise.resolve(new Response(ent.text, {
            status: ent.status || 200,
            headers: {"Content-Type": ent.ct || "application/json"}
          }));
        } catch(e) { /* fallthrough */ }
      }

      const p = ORIG_FETCH(u, init).then(async (resp)=>{
        try{
          const ct = (resp.headers && resp.headers.get) ? (resp.headers.get("content-type")||"") : "";
          // Cache only json/text to recreate safely
          if (ct.indexOf("application/json")>=0 || ct.indexOf("text/plain")>=0) {
            const t = await resp.clone().text();
            CACHE.set(key, {ts: Date.now(), inflight: null, text: t, status: resp.status, ct});
          } else {
            CACHE.set(key, {ts: Date.now(), inflight: null});
          }
        } catch(e){
          CACHE.set(key, {ts: Date.now(), inflight: null});
        }
        return resp;
      }).catch(err=>{
        CACHE.delete(key);
        throw err;
      });

      CACHE.set(key, {ts: now, inflight: p});
      return p;
    };

    console.log("[GateStoryV1][%s] fetch throttle installed (cooldown=%sms)", "VSP_P1_GATE_FETCH_THROTTLE_AND_GATE_ROOT_RID_V1", COOLDOWN_MS);
  } catch(e) { /* noop */ }
})();
""").strip("\n")

# Insert block near top: after first occurrence of "(=> {" or "(function" etc; safest: insert at very beginning
s2 = block + "\n\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] injected:", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK"

echo "== NEXT (browser) =="
echo "1) Console:"
echo "   localStorage.removeItem('vsp_rid_latest_v1'); localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "2) Ctrl+F5 /vsp5 (or Incognito)."
