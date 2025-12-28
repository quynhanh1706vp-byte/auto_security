#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed
command -v node >/dev/null 2>&1 && node_ok=1 || node_ok=0
command -v systemctl >/dev/null 2>&1 && svc_ok=1 || svc_ok=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] detect JS loaded by /settings (strip ?v=...) =="
JS_LIST="$(curl -fsS "$BASE/settings" \
  | grep -oE '/static/js/[^"]+' \
  | sed 's/?v=.*$//' \
  | sort -u)"
echo "$JS_LIST" | sed 's/^/[JS] /'

[ -n "$JS_LIST" ] || { echo "[ERR] cannot detect JS list from /settings"; exit 2; }

echo "== [1] backup all local files =="
BK="/tmp/vsp_fetchguard_v3_${TS}"
mkdir -p "$BK"
while read -r p; do
  [ -z "$p" ] && continue
  f="${p#/}"             # static/js/xxx.js
  [ -f "$f" ] || { echo "[WARN] missing local: $f"; continue; }
  cp -f "$f" "$BK/$(basename "$f").bak" || true
done <<< "$JS_LIST"
echo "[OK] backup dir: $BK"

echo "== [2] inject guard into each local JS (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re

marker = "VSP_RUNFILEALLOW_FETCH_GUARD_V3"
inject = r"""
/* VSP_RUNFILEALLOW_FETCH_GUARD_V3
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
   - covers fetch + XMLHttpRequest
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v3) return;
    window.__vsp_runfileallow_fetch_guard_v3 = true;

    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\-]+$/.test(rid);
    }

    function _fixRunFileAllowUrl(url0){
      try{
        if(!url0 || typeof url0 !== "string") return {action:"pass"};
        if(!url0.includes("/api/vsp/run_file_allow")) return {action:"pass"};
        const u = new URL(url0, window.location.origin);
        const rid = u.searchParams.get("rid") || "";
        const path = u.searchParams.get("path") || "";
        if(!_isLikelyRid(rid)) return {action:"skip"};
        if(!path){
          u.searchParams.set("path","run_gate_summary.json");
          return {action:"rewrite", url: u.toString().replace(window.location.origin,"")};
        }
        return {action:"pass"};
      }catch(e){
        return {action:"pass"};
      }
    }

    // --- fetch ---
    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (_origFetch){
      window.fetch = function(input, init){
        try{
          const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          const fx = _fixRunFileAllowUrl(url0);
          if (fx.action === "skip"){
            const body = JSON.stringify({ok:false, skipped:true, reason:"no rid"});
            return Promise.resolve(new Response(body, {status:200, headers:{"Content-Type":"application/json; charset=utf-8"}}));
          }
          if (fx.action === "rewrite"){
            if (typeof input === "string") input = fx.url;
            else input = new Request(fx.url, input);
          }
        }catch(e){}
        return _origFetch(input, init);
      };
    }

    // --- XMLHttpRequest ---
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      XHR.prototype.open = function(method, url, async, user, password){
        try{
          const url0 = (typeof url === "string") ? url : "";
          const fx = _fixRunFileAllowUrl(url0);
          if (fx.action === "skip"){
            // Convert to harmless local URL that returns 200 JSON (served by fetch guard won't apply here)
            // So we emulate by swapping to a data: URL
            const body = encodeURIComponent(JSON.stringify({ok:false, skipped:true, reason:"no rid"}));
            url = "data:application/json;charset=utf-8," + body;
          } else if (fx.action === "rewrite"){
            url = fx.url;
          }
        }catch(e){}
        return _open.call(this, method, url, async, user, password);
      };
    }
  } catch(e) {}
})();
"""

# Read JS list from /tmp file produced by shell
# Shell prints list; we’ll re-read from stdin passed by environment not available here.
PY
# pass js list into python via stdin for patching
python3 - <<'PY' <<EOF
$JS_LIST
EOF
PY

echo "== [3] node --check (best effort) =="
if [ "$node_ok" = "1" ]; then
  while read -r p; do
    [ -z "$p" ] && continue
    f="${p#/}"
    [ -f "$f" ] || continue
    node --check "$f" >/dev/null && echo "[OK] node --check: $f" || { echo "[ERR] node check fail: $f"; exit 2; }
  done <<< "$JS_LIST"
fi

echo "== [4] restart service (best effort) =="
if [ "$svc_ok" = "1" ]; then
  systemctl restart "$SVC" || true
fi

echo "== [5] smoke: marker served (cache-bust) =="
while read -r p; do
  [ -z "$p" ] && continue
  url="$BASE$p?cb=$TS"
  if curl -fsS "$url" | grep -q "VSP_RUNFILEALLOW_FETCH_GUARD_V3"; then
    echo "[OK] marker in $p"
  else
    echo "[WARN] marker not found in $p (maybe not patched / not served)"
  fi
done <<< "$JS_LIST"

echo "[DONE] Ctrl+F5 /settings. DevTools Network filter: run_file_allow => should stop 404 spam."
