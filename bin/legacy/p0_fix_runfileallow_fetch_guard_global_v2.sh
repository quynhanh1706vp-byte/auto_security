#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep
command -v node >/dev/null 2>&1 && node_ok=1 || node_ok=0
command -v systemctl >/dev/null 2>&1 && svc_ok=1 || svc_ok=0

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] pick common JS target =="
CANDS=(
  static/js/vsp_tabs3_common_v3.js
  static/js/vsp_ui_shell_v1.js
  static/js/vsp_p1_page_boot_v1.js
  static/js/vsp_topbar_commercial_v1.js
)
TARGET=""
for f in "${CANDS[@]}"; do
  if [ -f "$f" ]; then TARGET="$f"; break; fi
done
[ -n "$TARGET" ] || { echo "[ERR] cannot find common JS (tried: ${CANDS[*]})"; exit 2; }
echo "[OK] TARGET=$TARGET"
export TARGET

echo "== [1] backup =="
cp -f "$TARGET" "${TARGET}.bak_fetchguard_${TS}"
echo "[BACKUP] ${TARGET}.bak_fetchguard_${TS}"

echo "== [2] inject global fetch guard (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import os, re

target = Path(os.environ["TARGET"])
if not target.exists():
    raise SystemExit(f"[ERR] target not found: {target}")

s = target.read_text(encoding="utf-8", errors="replace")
marker = "VSP_RUNFILEALLOW_FETCH_GUARD_V1"

if marker in s:
    print("[INFO] marker already present; no change")
    raise SystemExit(0)

inject = r"""
/* VSP_RUNFILEALLOW_FETCH_GUARD_V1
   - prevent 404 spam when rid missing/invalid
   - auto add default path when missing
*/
(()=> {
  try {
    if (window.__vsp_runfileallow_fetch_guard_v1) return;
    window.__vsp_runfileallow_fetch_guard_v1 = true;

    const _origFetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_origFetch) return;

    function _isLikelyRid(rid){
      if(!rid || typeof rid !== "string") return false;
      if(rid.length < 6) return false;
      if(rid.includes("{") || rid.includes("}")) return false;
      return /^[A-Za-z0-9_\-]+$/.test(rid);
    }

    window.fetch = function(input, init){
      try {
        const url0 = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
        if (url0 && url0.includes("/api/vsp/run_file_allow")) {
          const u = new URL(url0, window.location.origin);
          const rid = u.searchParams.get("rid") || "";
          const path = u.searchParams.get("path") || "";

          if (!_isLikelyRid(rid)) {
            const body = JSON.stringify({ok:false, skipped:true, reason:"no rid"});
            return Promise.resolve(new Response(body, {
              status: 200,
              headers: {"Content-Type":"application/json; charset=utf-8"}
            }));
          }

          if (!path) {
            u.searchParams.set("path", "run_gate_summary.json");
            const fixed = u.toString().replace(window.location.origin, "");
            if (typeof input === "string") input = fixed;
            else input = new Request(fixed, input);
          }
        }
      } catch (e) {}
      return _origFetch(input, init);
    };
  } catch(e) {}
})();
"""

# inject after first "(()=>{" if present, else prepend
m = re.search(r'(\(\s*\)\s*=>\s*\{\s*)', s)
if m:
    pos = m.end()
    s2 = s[:pos] + "\n" + inject + "\n" + s[pos:]
else:
    s2 = inject + "\n" + s

target.write_text(s2, encoding="utf-8")
print("[OK] injected into", target)
PY

if [ "$node_ok" = "1" ]; then
  echo "== [3] node --check (best effort) =="
  node --check "$TARGET" >/dev/null && echo "[OK] node --check: $TARGET" || { echo "[ERR] node check fail: $TARGET"; exit 2; }
fi

echo "== [4] restart service (best effort) =="
if [ "$svc_ok" = "1" ]; then
  systemctl restart "$SVC" || true
fi

echo "== [5] smoke: marker served =="
JS_URL="/$(echo "$TARGET" | sed 's#^static/##')"
curl -fsS "$BASE$JS_URL" | grep -n "VSP_RUNFILEALLOW_FETCH_GUARD_V1" >/dev/null \
  && echo "[OK] guard marker served in $JS_URL" \
  || echo "[WARN] marker not found via curl (maybe different JS is loaded on page)"

echo "[DONE] Ctrl+F5 on /settings (DevTools filter: run_file_allow). 404 spam should stop."
