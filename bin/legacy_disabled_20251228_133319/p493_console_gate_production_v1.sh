#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p493_console_gate_${TS}"
mkdir -p "$OUT"

pick=""
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_console_patch_v1.js; do
  [ -f "$f" ] && { pick="$f"; break; }
done
[ -n "$pick" ] || { echo "[ERR] no target js found" | tee "$OUT/log.txt"; exit 2; }

cp -f "$pick" "$OUT/$(basename "$pick").bak_${TS}"
echo "[OK] target=$pick backup=$OUT/$(basename "$pick").bak_${TS}" | tee "$OUT/log.txt"

python3 - <<'PY' "$pick"
from pathlib import Path
p=Path(__import__("sys").argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_CONSOLE_GATE_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

snippet = r"""
/* VSP_CONSOLE_GATE_V1: commercial default silence; enable via ?debug=1 or localStorage.VSP_DEBUG=1 */
(function(){
  try{
    var qs = new URLSearchParams(location.search || "");
    var flag = (qs.get("debug") || localStorage.getItem("VSP_DEBUG") || "").toString().toLowerCase();
    var on = (flag === "1" || flag === "true" || flag === "on" || flag === "yes");
    window.VSP_DEBUG = !!on;
    if (on) { return; }
    var noop = function(){};
    if (window.console){
      // keep console.error, silence the rest
      if (console.log) console.log = noop;
      if (console.info) console.info = noop;
      if (console.debug) console.debug = noop;
      if (console.warn) console.warn = noop;
    }
  }catch(e){}
})();
"""

# Insert near top: after 'use strict' if present, else prepend
idx = s.find("'use strict'")
if idx != -1:
    # insert after that line
    lines=s.splitlines(True)
    out=[]
    inserted=False
    for line in lines:
        out.append(line)
        if (not inserted) and ("use strict" in line):
            out.append(snippet+"\n")
            inserted=True
    s2="".join(out)
else:
    s2=snippet+"\n"+s

p.write_text(s2, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[OK] patched. (tip) enable debug: add ?debug=1 or run localStorage.VSP_DEBUG=1 in console" | tee -a "$OUT/log.txt"
