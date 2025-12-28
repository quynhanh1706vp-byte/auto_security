#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl
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

echo "== [1] backup =="
BK="/tmp/vsp_fetchguard_v3b_${TS}"
mkdir -p "$BK"
while read -r web; do
  [ -z "$web" ] && continue
  local="${web#/}"   # static/js/xxx.js
  if [ -f "$local" ]; then
    cp -f "$local" "$BK/$(basename "$local").bak"
  else
    echo "[WARN] missing local: $local"
  fi
done <<< "$JS_LIST"
echo "[OK] backup dir: $BK"

echo "== [2] patch each local JS (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re, sys

marker = "VSP_RUNFILEALLOW_FETCH_GUARD_V3B"

inject = r"""
/* VSP_RUNFILEALLOW_FETCH_GUARD_V3B
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
   - covers fetch + XMLHttpRequest
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v3b) return;
    window.__vsp_runfileallow_fetch_guard_v3b = true;

    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\\-]+$/.test(rid);
    }

    function _fix(url0){
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

    // fetch
    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (_origFetch){
      window.fetch = function(input, init){
        try{
          const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          const fx = _fix(url0);
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

    // XHR
    const XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && XHR.prototype.open){
      const _open = XHR.prototype.open;
      XHR.prototype.open = function(method, url, async, user, password){
        try{
          const url0 = (typeof url === "string") ? url : "";
          const fx = _fix(url0);
          if (fx.action === "skip"){
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

def patch_file(path: Path) -> bool:
    s = path.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        print("[INFO] already:", path)
        return False
    # inject after first IIFE opener if possible
    m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
    if m:
        pos = m.end()
        s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
    else:
        s2 = inject + "\n" + s
    path.write_text(s2, encoding="utf-8")
    print("[OK] patched:", path)
    return True

# Read list from stdin (web paths)
web_paths = [ln.strip() for ln in sys.stdin.read().splitlines() if ln.strip().startswith("/static/js/")]
changed = 0
for web in web_paths:
    local = Path(web.lstrip("/"))  # static/js/xxx.js
    if not local.exists():
        print("[WARN] missing local:", local)
        continue
    if patch_file(local):
        changed += 1

print("[DONE] changed:", changed, "/", len(web_paths))
PY
# feed JS_LIST into python via stdin
<<< "$JS_LIST"

if [ "$node_ok" = "1" ]; then
  echo "== [3] node --check patched JS (best effort) =="
  while read -r web; do
    [ -z "$web" ] && continue
    local="${web#/}"
    [ -f "$local" ] || continue
    node --check "$local" >/dev/null && echo "[OK] node --check: $local" || { echo "[ERR] node check fail: $local"; exit 2; }
  done <<< "$JS_LIST"
fi

echo "== [4] restart service (best effort) =="
if [ "$svc_ok" = "1" ]; then
  systemctl restart "$SVC" || true
fi

echo "== [5] smoke: marker served (cache-bust) =="
while read -r web; do
  [ -z "$web" ] && continue
  if curl -fsS "$BASE$web?cb=$TS" | grep -q "VSP_RUNFILEALLOW_FETCH_GUARD_V3B"; then
    echo "[OK] marker in $web"
  else
    echo "[WARN] marker NOT found in $web"
  fi
done <<< "$JS_LIST"

echo "[DONE] Ctrl+F5 /settings. Network filter: run_file_allow => should stop 404 spam."
