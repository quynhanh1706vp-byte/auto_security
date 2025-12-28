#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep

# Common candidates
CANDS=(
  "static/js/vsp_runs_quick_actions_v1.js"
  "static/js/vsp_runs_tab_resolved_v1.js"
  "static/js/vsp_tabs4_autorid_v1.js"
  "static/js/vsp_bundle_commercial_v2.js"
)

pick=""
for f in "${CANDS[@]}"; do
  [ -f "$f" ] || continue
  if grep -qE "/runs|Runs & Reports|vsp-runs" "$f" 2>/dev/null; then pick="$f"; break; fi
done

# Fallback: search any js containing "/runs"
if [ -z "${pick:-}" ]; then
  pick="$(grep -RIl --include='*.js' -E '"/runs"|/runs' static/js | head -n 1 || true)"
fi

[ -n "${pick:-}" ] || { echo "[ERR] cannot find runs tab JS to patch"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "${pick}.bak_releasesbtn_${TS}"
echo "[BACKUP] ${pick}.bak_releasesbtn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("""'"$pick"'""")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P2_RELEASES_BUTTON_RUNS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Inject a global helper; safe/no-op if no toolbar exists
addon = r'''
/* VSP_P2_RELEASES_BUTTON_RUNS_V1 */
(function(){
  function addBtn(){
    // try common toolbar containers
    const cands = [
      document.querySelector(".vsp-top-actions"),
      document.querySelector(".vsp-toolbar"),
      document.querySelector("#vsp-dashboard-actions"),
      document.querySelector("header"),
      document.body
    ].filter(Boolean);
    const host = cands[0];
    if(!host) return;

    if(document.getElementById("vsp-btn-releases")) return;

    const b = document.createElement("button");
    b.id = "vsp-btn-releases";
    b.textContent = "Releases";
    b.style.cssText = "margin-left:8px;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:inherit;cursor:pointer;font-size:12px";
    b.onclick = () => window.open("/releases","_blank");

    // If there is already a button group, append near export/refresh
    const btnGroup = host.querySelector("button") ? host : null;
    (btnGroup || host).appendChild(b);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", addBtn);
  else addBtn();
})();
'''.strip("\n")+"\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8", errors="replace")
print("[OK] appended:", MARK, "file=", str(p))
PY

node --check "$pick" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P2_RELEASES_BUTTON_RUNS_V1" "$pick" | head -n 1 && echo "[OK] marker present"
echo "[OK] patched file: $pick"
