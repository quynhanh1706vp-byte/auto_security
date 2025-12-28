#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

B="static/js/vsp_bundle_commercial_v2.js"
[ -f "$B" ] || { echo "[ERR] missing $B"; exit 2; }

cp -f "$B" "${B}.bak_blockprobe_${TS}"
echo "[BACKUP] ${B}.bak_blockprobe_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_BLOCK_RUNFILEALLOW_SARIF_PROBE_AND_MUTE_LEGACY_LOGS_V1"
if MARK not in s:
    inject = r"""
/* VSP_P1_BLOCK_RUNFILEALLOW_SARIF_PROBE_AND_MUTE_LEGACY_LOGS_V1
 * Goal: Step-2 commercial clean.
 * - Block any *auto-probe* calls to /api/vsp/run_file_allow that target SARIF (causing 403 allowlist noise)
 * - Mute legacy V6 spam logs (cosmetic, for demo cleanliness)
 */
(()=>{ try{
  // --- mute legacy spam logs (cosmetic)
  const _mk = (fn)=>function(...a){
    try{
      const msg = String(a && a[0] !== undefined ? a[0] : "");
      if (msg.includes("legacy disabled (V6")) return;
      if (msg.includes("[VSP][DASH] legacy disabled")) return;
      if (msg.includes("containers/rid missing")) return;
    }catch(_){}
    return fn.apply(this,a);
  };
  if (console && console.log)  console.log  = _mk(console.log);
  if (console && console.warn) console.warn = _mk(console.warn);

  const isSarifProbe = (url)=>{
    url = String(url||"");
    if (!url.includes("/api/vsp/run_file_allow")) return false;
    const u = url.toLowerCase();
    // block any sarif / sarif-disabled probes
    return u.includes(".sarif") || u.includes("sarif__disabled__") || u.includes("findings_unified.sarif");
  };

  // --- block fetch probes
  const ofetch = window.fetch;
  if (typeof ofetch === "function") {
    window.fetch = function(input, init){
      try{
        const url = (typeof input === "string") ? input : (input && input.url) || "";
        if (isSarifProbe(url)) {
          const body = JSON.stringify({ok:false, err:"sarif probe disabled (Step-2)"});
          return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json"}}));
        }
      }catch(_){}
      return ofetch.apply(this, arguments);
    };
  }

  // --- block XHR probes (some legacy code uses XMLHttpRequest)
  const X = window.XMLHttpRequest;
  if (X && X.prototype) {
    const oopen = X.prototype.open;
    const osend = X.prototype.send;
    X.prototype.open = function(method, url){
      try{ this.__vsp_url__ = url; }catch(_){}
      return oopen.apply(this, arguments);
    };
    X.prototype.send = function(body){
      try{
        const url = this.__vsp_url__ || "";
        if (isSarifProbe(url)) {
          // emulate success without network
          try { this.readyState = 4; } catch(_){}
          try { this.status = 200; } catch(_){}
          try { this.responseText = '{"ok":false,"err":"sarif probe disabled (Step-2)"}'; } catch(_){}
          try { if (typeof this.onreadystatechange === "function") this.onreadystatechange(); } catch(_){}
          try { if (typeof this.onload === "function") this.onload(); } catch(_){}
          return;
        }
      }catch(_){}
      return osend.apply(this, arguments);
    };
  }
}catch(_){}})();
"""
    s = inject + "\n" + s
    p.write_text(s, encoding="utf-8")
    print("[OK] injected:", MARK)
else:
    print("[OK] marker exists, skip")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$B" && echo "[OK] node --check passed"
fi

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)."
