#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

RIDJS="static/js/vsp_rid_autofix_v1.js"
[ -f "$RIDJS" ] || { echo "[ERR] missing $RIDJS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$RIDJS" "${RIDJS}.bak_poll_${TS}"
echo "[BACKUP] ${RIDJS}.bak_poll_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p = Path("static/js/vsp_rid_autofix_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_AUTOFIX_POLL_V1"
if marker in s:
    print("[OK] poll already enabled")
    raise SystemExit(0)

# insert polling block right before the final '})();' of the IIFE by finding the end of async block call
insert = r"""
    /* VSP_P0_RID_AUTOFIX_POLL_V1 */
    try{
      const POLL_MS = 15000; // commercial-safe: low frequency
      let _last = "";
      try{ _last = localStorage.getItem("vsp_selected_rid") || ""; }catch(e){}
      setInterval(async ()=> {
        try{
          const j = await fetchJson(API_LATEST, 2000);
          const rid2 = (j && j.ok && j.rid) ? String(j.rid) : "";
          if (!rid2) return;
          if (!_last) {
            _last = rid2;
            setRid(rid2);
            return;
          }
          if (rid2 !== _last){
            _last = rid2;
            setRid(rid2);
          }
        }catch(e){}
      }, POLL_MS);
    }catch(e){}
"""

# put before the end of outer try/catch closing
# safest: inject before the line containing "(async ()=> {" (NO); better: inject after initial (async...) call block ends.
# We look for the pattern "})();" at end and insert before it (first from end).
idx = s.rfind("})();")
if idx == -1:
    raise SystemExit("[ERR] cannot locate end of IIFE")

s2 = s[:idx] + insert + "\n" + s[idx:]
p.write_text(s2, encoding="utf-8")
print("[OK] enabled poll in rid autofix")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$RIDJS" && echo "[OK] node --check rid js OK"
fi
