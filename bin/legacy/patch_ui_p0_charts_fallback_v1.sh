#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

FILES="$(grep -RIl "VSP_CHARTS_BOOT_SAFE_V2" . | head -n 20 || true)"
[ -n "$FILES" ] || { echo "[ERR] cannot find charts bootstrap file by marker VSP_CHARTS_BOOT_SAFE_V2"; exit 2; }

for F in $FILES; do
  echo "== PATCH: $F =="
  cp -f "$F" "$F.bak_p0_charts_${TS}"
  echo "[BACKUP] $F.bak_p0_charts_${TS}"

  python3 - <<'PY'
from pathlib import Path
import re

f = Path("""'"$F"'""")
s = f.read_text(encoding="utf-8", errors="ignore")
changed = 0

MARK = "P0_CHARTS_FALLBACK_V1"
if MARK not in s:
    header = r"""/* P0_CHARTS_FALLBACK_V1 */
(function(){
  try{
    if (typeof window === "undefined") return;
    if (typeof window.__VSP_P0_CHARTS_FALLBACK === "function") return;

    window.__VSP_P0_CHARTS_FALLBACK = function(reason){
      try{
        var sel = [
          "#vsp-charts-root","#vsp-dashboard-charts","#vsp-dash-charts",
          ".vsp-charts",".vsp-dashboard-charts"
        ];
        var host = null;
        for (var i=0;i<sel.length;i++){
          var el = document.querySelector(sel[i]);
          if (el) { host = el; break; }
        }
        if (!host) return;

        // don't overwrite real charts if they exist
        if (host.querySelector(".vsp-p0-charts-fallback")) return;

        var d = document.createElement("div");
        d.className = "vsp-p0-charts-fallback";
        d.style.cssText = "margin-top:10px;padding:10px;border:1px dashed rgba(255,255,255,.18);border-radius:10px;background:rgba(0,0,0,.18);font-size:12px;opacity:.9";
        d.textContent = "Charts unavailable (degraded): " + (reason || "missing data/engine");
        host.appendChild(d);
      }catch(_){}
    };
  }catch(_){}
})();
"""
    s = header + "\n" + s
    changed += 1

# Demote warn -> info for this module (avoid noisy console)
s2 = re.sub(r"console\.warn\(([^;]*VSP_CHARTS_BOOT_SAFE_V2[^;]*)\);", r"console.info(\1);", s)
if s2 != s:
    s = s2
    changed += 1

# When give-up happens, call fallback
# Replace: console.(warn/info)('...give up after', MAX_TRIES, ...)
pat = r"(console\.(?:warn|info)\(\s*['\"]\[VSP_CHARTS_BOOT_SAFE_V2\]\s*give up after[^;]*\);\s*\n\s*return\s*;)"
m = re.search(pat, s)
if m and ".__VSP_P0_CHARTS_FALLBACK(" not in m.group(0):
    repl = m.group(0).replace("return", "try{ if(window.__VSP_P0_CHARTS_FALLBACK) window.__VSP_P0_CHARTS_FALLBACK('give_up'); }catch(_){ }\n      return")
    s = s[:m.start()] + repl + s[m.end():]
    changed += 1

f.write_text(s, encoding="utf-8")
print("[OK] changed_blocks=", changed)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

echo "[DONE] charts fallback patch"
