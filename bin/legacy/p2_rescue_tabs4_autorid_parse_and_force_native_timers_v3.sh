#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_tabs4_autorid_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node; need python3; need grep; need head; need ls

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [0] Backup current (broken) file =="
cp -f "$F" "${F}.bak_broken_before_rescue_${TS}"
echo "[BACKUP] ${F}.bak_broken_before_rescue_${TS}"

echo "== [1] Find newest backup that parses OK (node) =="
pick=""
# include many patterns; newest first
for b in $(ls -1t "${F}".bak_* 2>/dev/null || true); do
  ok=0
  node - <<NODE >/dev/null 2>&1 || ok=1
const fs=require("fs");
new Function(fs.readFileSync("$b","utf8"));
NODE
  if [ "$ok" -eq 0 ]; then
    pick="$b"
    break
  fi
done

if [ -z "$pick" ]; then
  echo "[ERR] no parse-ok backup found for $F"
  echo "Hint: list backups: ls -1t ${F}.bak_* | head"
  exit 2
fi

echo "[RESTORE] $F <= $pick"
cp -f "$pick" "$F"

echo "== [2] Patch: add native timer snapshot near top (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_NATIVE_TIMER_SNAPSHOT_V1"
if marker not in s:
    inject = """/* VSP_NATIVE_TIMER_SNAPSHOT_V1 */
(function(){
  try{
    if(!window.__vspNativeSetInterval) window.__vspNativeSetInterval = window.setInterval.bind(window);
    if(!window.__vspNativeClearInterval) window.__vspNativeClearInterval = window.clearInterval.bind(window);
    if(!window.__vspNativeSetTimeout) window.__vspNativeSetTimeout = window.setTimeout.bind(window);
    if(!window.__vspNativeClearTimeout) window.__vspNativeClearTimeout = window.clearTimeout.bind(window);
  }catch(e){}
})();
"""
    m=re.search(r'(?m)^\s*[\'"]use strict[\'"]\s*;\s*', s)
    if m:
        pos=m.end()
        s=s[:pos]+"\n"+inject+"\n"+s[pos:]
    else:
        s=inject+"\n"+s
p.write_text(s, encoding="utf-8")
print("[OK] snapshot ensured")
PY

echo "== [3] Patch: force native timers at end (idempotent) =="
python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_tabs4_autorid_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
tag="VSP_FORCE_NATIVE_TIMERS_V1"
if tag not in s:
    block = r"""
/* VSP_FORCE_NATIVE_TIMERS_V1 */
(function(){
  try{
    if(window.__vspNativeSetInterval) window.setInterval = window.__vspNativeSetInterval;
    if(window.__vspNativeClearInterval) window.clearInterval = window.__vspNativeClearInterval;
    if(window.__vspNativeSetTimeout) window.setTimeout = window.__vspNativeSetTimeout;
    if(window.__vspNativeClearTimeout) window.clearTimeout = window.__vspNativeClearTimeout;
  }catch(e){}
})();
"""
    s = s.rstrip() + "\n" + block + "\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] appended force-native block")
else:
    print("[OK] force-native already present")
PY

echo "== [4] Parse check (node) =="
node - <<'NODE'
const fs=require("fs");
const f="static/js/vsp_tabs4_autorid_v1.js";
new Function(fs.readFileSync(f,"utf8"));
console.log("[OK] parse ok:", f);
NODE

echo "== [5] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [6] Smoke markers in served JS =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
curl -fsS --max-time 3 "$BASE/static/js/vsp_tabs4_autorid_v1.js" | grep -n "VSP_NATIVE_TIMER_SNAPSHOT_V1\|VSP_FORCE_NATIVE_TIMERS_V1" | head -n 20 || true
echo "[DONE] Ctrl+Shift+R on /vsp5 and re-check Console. Must NOT see '_window is not defined'."
