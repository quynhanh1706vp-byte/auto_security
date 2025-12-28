#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need grep
command -v systemctl >/dev/null 2>&1 || true

SHIM="static/js/vsp_early_safe_shim_v1.js"
MARK="VSP_P3K22_EARLY_SAFE_SHIM_V1"

mkdir -p static/js templates

# 1) Create shim (idempotent)
if [ ! -f "$SHIM" ] || ! grep -q "$MARK" "$SHIM" 2>/dev/null; then
  [ -f "$SHIM" ] && cp -f "$SHIM" "${SHIM}.bak_p3k22_${TS}" && echo "[BACKUP] ${SHIM}.bak_p3k22_${TS}"
  cat > "$SHIM" <<'JS'
/* === VSP_P3K22_EARLY_SAFE_SHIM_V1 ===
   Run BEFORE other scripts (autorid/tabs5) to avoid Firefox abort/noise.
   - If ?rid= exists: short-circuit /api/vsp/rid_latest* to return URL rid immediately.
   - Rewrite XHR rid_latest -> rid_latest_v3?rid=...
   - Swallow timeout/NetworkError unhandled rejections (commercial-safe)
*/
(function(){
  try{
    if (window.__VSP_P3K22__) return;
    window.__VSP_P3K22__ = true;

    const usp = new URLSearchParams(location.search || "");
    const rid = (usp.get("rid") || "").trim();
    const debug = (usp.get("debug_ui") === "1");
    if (rid) window.__VSP_RID_LOCKED__ = rid;

    function softErr(x){
      const msg = String((x && (x.message || x.reason || x)) || "").toLowerCase();
      return msg.includes("timeout") || msg.includes("networkerror") || msg.includes("ns_binding_aborted");
    }

    window.addEventListener("unhandledrejection", function(e){
      try{ if (!debug && softErr(e && e.reason)) e.preventDefault(); }catch(_){}
    });
    window.addEventListener("error", function(e){
      try{ if (!debug && softErr(e && e.error)) e.preventDefault(); }catch(_){}
    });

    if (!debug && rid && typeof window.fetch === "function"){
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && url.indexOf("/api/vsp/rid_latest") !== -1){
            const body = JSON.stringify({ok:true, rid: rid, mode:"url_rid"});
            return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json"}}));
          }
        }catch(_){}
        return _fetch(input, init);
      };
    }

    if (!debug && rid && window.XMLHttpRequest && window.XMLHttpRequest.prototype){
      const _open = window.XMLHttpRequest.prototype.open;
      window.XMLHttpRequest.prototype.open = function(method, url){
        try{
          const u = String(url || "");
          if (u.indexOf("/api/vsp/rid_latest") !== -1){
            const nu = "/api/vsp/rid_latest_v3?rid=" + encodeURIComponent(rid) + "&mode=url_rid";
            return _open.call(this, method, nu, true);
          }
        }catch(_){}
        return _open.apply(this, arguments);
      };
    }
  }catch(_){}
})();
JS
  echo "[OK] wrote $SHIM"
else
  echo "[OK] shim already present: $SHIM"
fi

node -c "$SHIM" >/dev/null 2>&1 && echo "[OK] node -c: $SHIM"

# 2) Inject shim into templates that serve /vsp5 (find any template containing tabs5/autorid)
python3 - <<'PY'
from pathlib import Path
import re, time

shim_tag = '<script src="/static/js/vsp_early_safe_shim_v1.js?v=early_safe_v1"></script>'
targets=[]

for tp in Path("templates").rglob("*.html"):
    s = tp.read_text(encoding="utf-8", errors="replace")
    if "vsp_bundle_tabs5_v1.js" in s or "vsp_tabs4_autorid_v1.js" in s:
        targets.append(tp)

if not targets:
    print("[WARN] no template matched (no tabs5/autorid include found).")
    raise SystemExit(0)

for tp in targets:
    s = tp.read_text(encoding="utf-8", errors="replace")
    if "vsp_early_safe_shim_v1.js" in s:
        print("[OK] already injected:", tp)
        continue

    # prefer insert BEFORE autorid, else before tabs5, else at end of <head>
    def insert_before(pattern):
        nonlocal_s = s
        m = re.search(pattern, nonlocal_s, flags=re.I)
        if not m: return None
        return nonlocal_s[:m.start()] + shim_tag + "\n" + nonlocal_s[m.start():]

    out = insert_before(r'<script[^>]+vsp_tabs4_autorid_v1\.js[^>]*></script>')
    if out is None:
        out = insert_before(r'<script[^>]+vsp_bundle_tabs5_v1\.js[^>]*></script>')
    if out is None:
        m = re.search(r'</head\s*>', s, flags=re.I)
        if m:
            out = s[:m.start()] + shim_tag + "\n" + s[m.start():]
        else:
            out = shim_tag + "\n" + s

    bak = tp.with_suffix(tp.suffix + f".bak_p3k22_{int(time.time())}")
    bak.write_text(s, encoding="utf-8")
    tp.write_text(out, encoding="utf-8")
    print("[PATCH] injected into", tp, "backup=", bak.name)
PY

# 3) restart
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }
fi

# 4) quick smoke: HTML contains shim
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${RID_SMOKE:-VSP_CI_20251219_092640}"
html="$(curl -fsS "$BASE/vsp5?rid=$RID" | head -n 250)"
echo "$html" | grep -n "vsp_early_safe_shim_v1.js" >/dev/null && echo "[OK] shim present in /vsp5 HTML" || echo "[WARN] shim not found in first 250 lines"
echo "[DONE] p3k22_inject_early_safe_shim_before_all_v1"
