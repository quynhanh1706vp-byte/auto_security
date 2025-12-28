#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[TS]=$TS"

# Only patch real JS under static/js
FILES="$(grep -RIl --include='*.js' "VSP_CHARTS_BOOT_SAFE_V2" static/js | head -n 20 || true)"
[ -n "$FILES" ] || { echo "[ERR] cannot find charts bootstrap JS by marker VSP_CHARTS_BOOT_SAFE_V2 under static/js"; exit 2; }

for F in $FILES; do
  echo "== PATCH: $F =="
  cp -f "$F" "$F.bak_p0_charts_${TS}"
  echo "[BACKUP] $F.bak_p0_charts_${TS}"

  TARGET_FILE="$F" python3 - <<'PY'
import os, re
from pathlib import Path

f = Path(os.environ["TARGET_FILE"])
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
        var sel = ["#vsp-charts-root","#vsp-dashboard-charts","#vsp-dash-charts",".vsp-charts",".vsp-dashboard-charts"];
        var host = null;
        for (var i=0;i<sel.length;i++){
          var el = document.querySelector(sel[i]);
          if (el) { host = el; break; }
        }
        if (!host) return;
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

# Demote warn -> info for give-up spam
s2 = s.replace('console.warn("[VSP_CHARTS_BOOT_SAFE_V2] give up after', 'console.info("[VSP_CHARTS_BOOT_SAFE_V2] give up after')
if s2 != s:
    s = s2
    changed += 1

# When give-up, call fallback best-effort (don’t block)
pat = r"(console\.(?:warn|info)\(\s*['\"]\[VSP_CHARTS_BOOT_SAFE_V2\]\s*give up after[^;]*\);\s*)"
m = re.search(pat, s)
if m and "__VSP_P0_CHARTS_FALLBACK" not in s[m.start():m.start()+400]:
    insert = m.group(1) + "try{ if(window.__VSP_P0_CHARTS_FALLBACK) window.__VSP_P0_CHARTS_FALLBACK('give_up'); }catch(_){ }\n"
    s = s[:m.start()] + insert + s[m.end():]
    changed += 1

f.write_text(s, encoding="utf-8")
print("[OK] changed_blocks=", changed, "file=", f)
PY

  node --check "$F" >/dev/null && echo "[OK] node --check $F"
done

echo "[DONE] charts fallback patch v2"
