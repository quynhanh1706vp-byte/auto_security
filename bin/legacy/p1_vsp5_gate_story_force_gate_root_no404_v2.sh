#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_gate_root_proxy_v2_${TS}"
echo "[BACKUP] ${F}.bak_gate_root_proxy_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# remove old proxy v1 block if present (safe)
s = re.sub(r'/\*\s*VSP_P1_GATE_ROOT_PROXY_V1[\s\S]*?\)\(\);\s*', '', s, count=1)

marker = "VSP_P1_GATE_ROOT_PROXY_V2"
if marker in s:
    print("[SKIP] already patched V2")
    raise SystemExit(0)

proxy = textwrap.dedent(r"""
/* VSP_P1_GATE_ROOT_PROXY_V2
 * Commercial fix: stop probing wrong RID via BOTH fetch + XMLHttpRequest.
 * - Wait /api/vsp/runs => rid_latest_gate_root || rid_latest_gate || rid_latest
 * - Rewrite /api/vsp/run_file_allow:
 *     rid  = gate_root rid
 *     path = run_gate_summary.json
 */
(()=> {
  try {
    if (window.__vsp_p1_gate_root_proxy_v2) return;
    window.__vsp_p1_gate_root_proxy_v2 = true;

    const ORIGIN = location.origin;

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
      } catch(e){ return ""; }
    };

    const cachedRid = ()=> {
      try {
        return (localStorage.getItem("vsp_rid_latest_gate_root_v1")
          || localStorage.getItem("vsp_rid_latest_v1")
          || "").toString().trim();
      } catch(e){ return ""; }
    };

    const RUNS_URL = ORIGIN + "/api/vsp/runs?limit=10&_=" + Date.now();
    window.__vsp_gate_root_rid_promise = window.__vsp_gate_root_rid_promise
      || fetch(RUNS_URL, {cache:"no-store"})
          .then(r => r.json().catch(()=>null))
          .then(j => pickRid(j) || cachedRid())
          .catch(()=> cachedRid());

    const rewriteRunFileAllow = (url0, rid)=> {
      const u = new URL(url0, ORIGIN);
      if (rid) u.searchParams.set("rid", rid);
      u.searchParams.set("path", "run_gate_summary.json");
      return u.toString();
    };

    // ---- fetch hook ----
    const origFetch = window.fetch.bind(window);
    window.fetch = function(input, init){
      try{
        const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        if (url0 && url0.indexOf("/api/vsp/run_file_allow") >= 0) {
          return window.__vsp_gate_root_rid_promise.then((rid)=>{
            const url1 = rewriteRunFileAllow(url0, rid);
            if (typeof input !== "string" && input && input.url) {
              const req = new Request(url1, input);
              return origFetch(req, init);
            }
            return origFetch(url1, init);
          });
        }
      }catch(e){}
      return origFetch(input, init);
    };

    // ---- XMLHttpRequest hook (this is the missing piece) ----
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype) {
      const _open = XHR.prototype.open;
      const _send = XHR.prototype.send;

      XHR.prototype.open = function(method, url, async, user, password){
        try{
          const url0 = (url || "").toString();
          if (url0.indexOf("/api/vsp/run_file_allow") >= 0) {
            // delay open until send, after we know rid
            this.__vsp_gate_root_pending_open = [method, url0, async, user, password];
            this.__vsp_gate_root_is_pending = true;
            return; // do NOT call original open now
          }
        }catch(e){}
        return _open.apply(this, arguments);
      };

      XHR.prototype.send = function(body){
        try{
          if (this.__vsp_gate_root_is_pending && this.__vsp_gate_root_pending_open) {
            const args = this.__vsp_gate_root_pending_open;
            this.__vsp_gate_root_is_pending = false;
            this.__vsp_gate_root_pending_open = null;

            const origUrl = args[1];
            const self = this;
            return window.__vsp_gate_root_rid_promise.then((rid)=>{
              const url1 = rewriteRunFileAllow(origUrl, rid);
              _open.call(self, args[0], url1, args[2], args[3], args[4]);
              return _send.call(self, body);
            });
          }
        }catch(e){}
        return _send.apply(this, arguments);
      };
    }

    console.log("[GateStoryV1][%s] installed", "VSP_P1_GATE_ROOT_PROXY_V2");
  } catch(e){}
})();
""").strip() + "\n\n"

p.write_text(proxy + s, encoding="utf-8")
print("[OK] patched:", p)
PY

echo "== verify marker =="
grep -n "VSP_P1_GATE_ROOT_PROXY_V2" -n "$F" | head -n 5 || true

echo
echo "NOW do in browser console:"
echo "  localStorage.removeItem('vsp_rid_latest_v1');"
echo "  localStorage.removeItem('vsp_rid_latest_gate_root_v1');"
echo "Then Ctrl+F5 /vsp5 (or Incognito)."
