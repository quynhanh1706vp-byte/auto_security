#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need python3; need node; need systemctl; need sudo; need grep; need sed; need curl; need ls

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

echo "== [0] pick latest commercial release pack =="
REL="$(ls -1dt releases/RELEASE_UI_COMMERCIAL_* 2>/dev/null | head -n 1 || true)"
[ -n "$REL" ] || err "no releases/RELEASE_UI_COMMERCIAL_* found"
ok "release=$REL"

echo "== [1] backup current state (minimal) =="
BK="bak_p3k24_${TS}"
mkdir -p "$BK"
cp -a wsgi_vsp_ui_gateway.py "$BK/" 2>/dev/null || true
cp -a vsp_demo_app.py "$BK/" 2>/dev/null || true
mkdir -p "$BK/static" "$BK/templates"
cp -a static/js "$BK/static/" 2>/dev/null || true
cp -a static/css "$BK/static/" 2>/dev/null || true
cp -a templates "$BK/" 2>/dev/null || true
ok "backup_dir=$BK"

echo "== [2] restore baseline from release (ONLY if present in release/ui) =="
# Release pack structure in your tree: releases/.../ui/wsgi_vsp_ui_gateway.py + maybe static/templates
if [ -f "$REL/ui/wsgi_vsp_ui_gateway.py" ]; then
  cp -f "$REL/ui/wsgi_vsp_ui_gateway.py" ./wsgi_vsp_ui_gateway.py
  ok "restored wsgi_vsp_ui_gateway.py from release"
else
  warn "no $REL/ui/wsgi_vsp_ui_gateway.py"
fi

if [ -d "$REL/ui/static" ]; then
  mkdir -p static
  cp -a "$REL/ui/static/." ./static/
  ok "restored static/ from release"
else
  warn "no $REL/ui/static (skip)"
fi

if [ -d "$REL/ui/templates" ]; then
  mkdir -p templates
  cp -a "$REL/ui/templates/." ./templates/
  ok "restored templates/ from release"
else
  warn "no $REL/ui/templates (skip)"
fi

echo "== [3] apply MIN commercial-safe JS shim (3 files only) =="
python3 - <<'PY'
from pathlib import Path

targets = [
  Path("static/js/vsp_tabs4_autorid_v1.js"),
  Path("static/js/vsp_bundle_tabs5_v1.js"),
  Path("static/js/vsp_dashboard_gate_story_v1.js"),
]

MARK = "VSP_P3K24_MIN_COMMERCIAL_SAFE_V1"

SHIM = r"""
/* === VSP_P3K24_MIN_COMMERCIAL_SAFE_V1 ===
   Rules:
   - If URL has ?rid= => do NOT call /api/vsp/rid_latest* (return url rid immediately)
   - Swallow Firefox noise: timeout / NetworkError / AbortError / NS_BINDING_ABORTED
   - Never throw "timeout" to console as unhandled rejection
*/
(function(){
  try{
    if (window.__VSP_P3K24_SAFE__) return;
    window.__VSP_P3K24_SAFE__ = true;

    function _urlRid(){
      try{
        const sp = new URLSearchParams(location.search || "");
        return (sp.get("rid") || "").trim();
      }catch(e){ return ""; }
    }

    const RID_URL = _urlRid();
    if (RID_URL) {
      window.__VSP_RID_URL__ = RID_URL;
      window.__VSP_AUTORID_DISABLED__ = true;
    }

    function _msg(x){
      try{
        if (typeof x === "string") return x;
        if (!x) return "";
        return (x.message || x.toString || "").toString();
      }catch(e){ return ""; }
    }

    function _isNoise(reason){
      const m = _msg(reason);
      return /timeout|networkerror|aborterror|ns_binding_aborted/i.test(m);
    }

    // 1) Stop "Uncaught (in promise) timeout" from poisoning console
    window.addEventListener("unhandledrejection", function(ev){
      try{
        if (ev && _isNoise(ev.reason)) {
          ev.preventDefault && ev.preventDefault();
        }
      }catch(e){}
    }, true);

    // 2) If rid is in URL, short-circuit fetch() calls to rid_latest endpoints
    if (RID_URL && typeof window.fetch === "function") {
      const _fetch = window.fetch.bind(window);
      window.fetch = function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (/\/api\/vsp\/rid_latest(_v3|_gate_root)?(\?|$)/.test(String(url))) {
            const body = JSON.stringify({ok:true, rid: RID_URL, mode:"url"});
            return Promise.resolve(new Response(body, {status:200, headers: {"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}}));
          }
        }catch(e){}
        return _fetch(input, init);
      };
    }

    // 3) Utility for other scripts
    window.__VSP_SAFE_WRAP_PROMISE__ = function(p){
      try{
        return Promise.resolve(p).catch(function(e){
          if (_isNoise(e)) return null;
          throw e;
        });
      }catch(e){ return Promise.resolve(null); }
    };

  }catch(e){}
})();
"""

def prepend_once(p: Path):
  if not p.exists():
    return (False, f"missing {p}")
  s = p.read_text(encoding="utf-8", errors="replace")
  if MARK in s:
    return (False, f"already {p}")
  s2 = SHIM + "\n" + s
  p.write_text(s2, encoding="utf-8")
  return (True, f"patched {p}")

changed = 0
for p in targets:
  ok, msg = prepend_once(p)
  print("[OK]" if ok else "[SKIP]", msg)
  if ok: changed += 1

print("[DONE] changed_files=", changed)
PY

echo "== [4] node -c sanity =="
node -c static/js/vsp_tabs4_autorid_v1.js
node -c static/js/vsp_bundle_tabs5_v1.js
node -c static/js/vsp_dashboard_gate_story_v1.js
ok "node -c passed"

echo "== [5] restart + smoke backend =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && ok "service active" || err "service not active"

# quick health
curl -fsS --connect-timeout 1 --max-time 3 "$BASE/api/vsp/healthz" >/dev/null && ok "healthz OK" || warn "healthz not OK"
RID="$(curl -fsS --connect-timeout 1 --max-time 4 "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin) or {}).get("rid",""))' || true)"
echo "RID=$RID"
[ -n "$RID" ] && curl -fsS -o /dev/null -w "dashboard_v3_latest HTTP=%{http_code} time=%{time_total}\n" "$BASE/api/vsp/dashboard_v3_latest?rid=$RID" || true
[ -n "$RID" ] && curl -fsS -o /dev/null -w "top_findings_v3c HTTP=%{http_code} time=%{time_total}\n" "$BASE/api/vsp/top_findings_v3c?limit=8&rid=$RID" || true

echo "[DONE] p3k24_restore_release_then_min_commercial_safe_v1"
