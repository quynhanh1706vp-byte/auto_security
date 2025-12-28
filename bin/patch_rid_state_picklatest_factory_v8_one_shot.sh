#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_rid_state_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "$F.bak_picklatest_factory_v8_${TS}" && echo "[BACKUP] $F.bak_picklatest_factory_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, os

ts=os.environ.get("TS","")
p=Path("static/js/vsp_rid_state_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) remove older blocks (best-effort)
markers = [
  ("/* VSP_RID_PICKLATEST_FACTORY_V8_BEGIN */","/* VSP_RID_PICKLATEST_FACTORY_V8_END */"),
  ("/* VSP_RID_PICKLATEST_GUARD_V6_BEGIN */","/* VSP_RID_PICKLATEST_GUARD_V6_END */"),
  ("/* VSP_RID_STATE_CRASHFIX_V7_BEGIN */","/* VSP_RID_STATE_CRASHFIX_V7_END */"),
  ("/* VSP_RID_STATE_CRASHFIX_V3B_BEGIN */","/* VSP_RID_STATE_CRASHFIX_V3B_END */"),
  ("/* VSP_RID_PICKLATEST_OVERRIDE_FORCE_V5_BEGIN */","/* VSP_RID_PICKLATEST_OVERRIDE_FORCE_V5_END */"),
]
for b,e in markers:
  s = re.sub(re.escape(b)+r"[\s\S]*?"+re.escape(e)+r"\n?", "", s)

# 2) prepend SAFE FACTORY (always returns a callable function)
block = r'''/* VSP_RID_PICKLATEST_FACTORY_V8_BEGIN */
(function(){
  'use strict';
  const G = globalThis;
  if (G.__VSP_RID_PICKLATEST_FACTORY_V8_INSTALLED) return;
  G.__VSP_RID_PICKLATEST_FACTORY_V8_INSTALLED = 1;

  // Always return a callable function (async) to avoid "j is not a function"
  G.__VSP_RID_PICKLATEST_FACTORY = function(){
    const ov = G.VSP_RID_PICKLATEST_OVERRIDE_V1;

    // default callable: returns null (no override)
    const fallback = async function(){ return null; };

    try {
      if (typeof ov !== 'function') return fallback;

      // ov can be:
      //  (A) factory: ov(...) -> function
      //  (B) direct:  ov(...) -> string/null/promise
      const out = ov.apply(null, arguments);

      if (typeof out === 'function') {
        return out; // factory mode OK
      }

      // promise mode -> wrap into callable
      if (out && typeof out.then === 'function') {
        return async function(){
          try {
            const v = await out;
            // if promise resolves to function => call it
            if (typeof v === 'function') return await v.apply(null, arguments);
            // else treat as value (rid string or null)
            if (typeof v === 'string' && v.trim()) return v.trim();
          } catch(e) {
            console.warn("[VSP_RID_FACTORY_V8] override promise failed:", e);
          }
          return null;
        };
      }

      // value mode -> wrap into callable
      return async function(){
        if (typeof out === 'string' && out.trim()) return out.trim();
        return null;
      };

    } catch(e) {
      console.warn("[VSP_RID_FACTORY_V8] override crashed:", e);
      return fallback;
    }
  };

  console.log("[VSP_RID_FACTORY_V8] installed");
})();
/* VSP_RID_PICKLATEST_FACTORY_V8_END */

'''
s = block + "\n" + s

# 3) Replace call-sites that assume factory:
#    VSP_RID_PICKLATEST_OVERRIDE_V1(....)  ==> globalThis.__VSP_RID_PICKLATEST_FACTORY(....)
s = re.sub(r'\bVSP_RID_PICKLATEST_OVERRIDE_V1\b(?=\s*\()',
           'globalThis.__VSP_RID_PICKLATEST_FACTORY', s)

p.write_text(s, encoding="utf-8")
print("[OK] rid_state v8 factory installed + override calls replaced")
PY

node --check "$F" >/dev/null && echo "[OK] rid_state JS syntax OK"

# bump cache param in templates (avoid stale v=)
for T in templates/vsp_4tabs_commercial_v1.html templates/vsp_dashboard_2025.html; do
  [ -f "$T" ] || continue
  cp -f "$T" "$T.bak_rid_v8_${TS}" && echo "[BACKUP] $T.bak_rid_v8_${TS}"
  python3 - <<PY
import re
from pathlib import Path
p=Path("$T")
s=p.read_text(encoding="utf-8", errors="replace")
# normalize src to: /static/js/vsp_rid_state_v1.js?v=TS
s=re.sub(r'(/static/js/vsp_rid_state_v1\.js\?v=)[^"\']*', r'\\1$TS', s)
p.write_text(s, encoding="utf-8")
print("[OK] bumped rid_state cache in", "$T")
PY
done

echo "[DONE] V8 applied. Restart 8910 + hard refresh Ctrl+Shift+R."
