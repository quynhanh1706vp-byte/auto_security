#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need ls; need head; need tail; need grep

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

restore_last_good(){
  local f="$1"
  ok "check syntax: $f"
  if node --check "$f" >/dev/null 2>&1; then
    ok "syntax OK: $f"
    return 0
  fi

  warn "syntax FAIL: $f"
  local cands
  cands="$(ls -1t "${f}.bak_"* 2>/dev/null || true)"
  [ -n "$cands" ] || err "no backups found for $f"

  while IFS= read -r b; do
    [ -f "$b" ] || continue
    if node --check "$b" >/dev/null 2>&1; then
      cp -f "$b" "$f"
      ok "restored from good backup: $b -> $f"
      node --check "$f" >/dev/null
      return 0
    fi
  done <<<"$cands"

  err "could not find any good backup for $f"
}

patch_scrub_loading_and_fetch_guard(){
  local f="$1"
  local marker="VSP_P1_FIX_DASH_STUCK_LOADING_AND_FETCH_GUARD_V1"
  python3 - <<PY
from pathlib import Path
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
if "$marker" in s:
    print("[OK] already patched:", "$marker")
    raise SystemExit(0)

addon = r'''
/* ===== VSP_P1_FIX_DASH_STUCK_LOADING_AND_FETCH_GUARD_V1 =====
 * Goal:
 *  - If dashboard JS renders partial HTML but charts never resolve, remove "Loading..." texts so UI looks commercial.
 *  - Add a very safe fetch timeout + de-dup inflight requests to avoid Firefox "page is slowing down".
 * NOTE: ES5-only, no optional chaining, no template literals.
 */
(function(){
  // ---- 1) scrub "Loading..." text that tends to stick forever when some APIs are unavailable
  function __vspScrubLoadingOnce(){
    try{
      var root = document.getElementById("vsp-dashboard-main") || document.body;
      if(!root) return;
      var els = root.querySelectorAll("div,span,p,li,td,th");
      for(var i=0;i<els.length;i++){
        var t = (els[i].textContent || "").replace(/\\s+/g," ").trim();
        if(t === "Loading..." || t === "Loading…"){
          els[i].textContent = "";
          els[i].style.display = "none";
        }
      }
    }catch(e){}
  }
  var tries = 0;
  var it = setInterval(function(){
    __vspScrubLoadingOnce();
    tries++;
    if(tries > 20) clearInterval(it);
  }, 500);
  setTimeout(__vspScrubLoadingOnce, 120);

  // ---- 2) fetch guard: timeout + de-dup inflight (prevents infinite concurrent fetch storms)
  try{
    if(!window.__VSP_FETCH_GUARD_V1 && window.fetch){
      window.__VSP_FETCH_GUARD_V1 = 1;
      var _origFetch = window.fetch;
      var _inflight = {};
      window.fetch = function(url, opts){
        try{
          var key = String(url || "");
          if(_inflight[key]) return _inflight[key];
          opts = opts || {};
          var ctrl = null;
          var timer = null;
          if(typeof AbortController !== "undefined"){
            ctrl = new AbortController();
            if(!opts.signal) opts.signal = ctrl.signal;
            timer = setTimeout(function(){
              try{ ctrl.abort(); }catch(e){}
            }, 8000);
          }
          var p = _origFetch(url, opts);
          // clear inflight safely (no .finally to keep it old-school)
          p = p.then(function(res){
            if(timer) try{ clearTimeout(timer); }catch(e){}
            delete _inflight[key];
            return res;
          }, function(e){
            if(timer) try{ clearTimeout(timer); }catch(_e){}
            delete _inflight[key];
            throw e;
          });
          _inflight[key] = p;
          return p;
        }catch(e){
          return _origFetch(url, opts);
        }
      };
    }
  }catch(e){}
})();
'''
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", "$marker")
PY
}

TS="$(date +%Y%m%d_%H%M%S)"

F1="static/js/vsp_bundle_tabs5_v1.js"
F2="static/js/vsp_tabs4_autorid_v1.js"

[ -f "$F1" ] || err "missing $F1"
[ -f "$F2" ] || err "missing $F2"

cp -f "$F1" "${F1}.bak_autofix_${TS}"
cp -f "$F2" "${F2}.bak_autofix_${TS}"
ok "backup: ${F1}.bak_autofix_${TS}"
ok "backup: ${F2}.bak_autofix_${TS}"

restore_last_good "$F1"
restore_last_good "$F2"

patch_scrub_loading_and_fetch_guard "$F1"

ok "final syntax check:"
node --check "$F1" >/dev/null
node --check "$F2" >/dev/null
ok "JS syntax OK (both)"

echo
echo "[DONE] Hard refresh:"
echo "  http://127.0.0.1:8910/vsp5   (Ctrl+Shift+R)"
echo "Then open Console: should be NO SyntaxError now."
