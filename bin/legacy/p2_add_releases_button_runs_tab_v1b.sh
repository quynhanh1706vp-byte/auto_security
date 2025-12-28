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
  if grep -qE 'Runs|/runs|vsp-runs|runs_quick' "$f" 2>/dev/null; then
    pick="$f"; break
  fi
done

if [ -z "${pick:-}" ]; then
  pick="$(grep -RIl --include='*.js' -E '"/runs"|/runs|Runs & Reports' static/js | head -n 1 || true)"
fi

[ -n "${pick:-}" ] || { echo "[ERR] cannot find runs tab JS to patch under static/js"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "${pick}.bak_releasesbtn_${TS}"
echo "[BACKUP] ${pick}.bak_releasesbtn_${TS}"

python3 - "$pick" <<'PY'
from pathlib import Path
import sys

js_path = sys.argv[1]
p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_RELEASES_BUTTON_RUNS_V1B"
if MARK in s:
    print("[OK] already patched:", MARK, "file=", js_path)
    raise SystemExit(0)

addon = r'''
/* VSP_P2_RELEASES_BUTTON_RUNS_V1B
   Adds a "Releases" button that opens /releases in a new tab.
*/
(function(){
  function _host(){
    return (
      document.querySelector(".vsp-top-actions") ||
      document.querySelector(".vsp-toolbar") ||
      document.querySelector("#vsp-dashboard-actions") ||
      document.querySelector("header") ||
      document.body
    );
  }

  function addBtn(){
    const h = _host();
    if(!h) return;
    if(document.getElementById("vsp-btn-releases")) return;

    const b = document.createElement("button");
    b.id = "vsp-btn-releases";
    b.type = "button";
    b.textContent = "Releases";
    b.title = "Open Release Center";
    b.style.cssText = "margin-left:8px;padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:inherit;cursor:pointer;font-size:12px";
    b.addEventListener("click", function(){ window.open("/releases","_blank"); });

    // Append near existing buttons if possible
    const btnRow = h.querySelector("button") ? h : null;
    (btnRow || h).appendChild(b);
  }

  // runs page may rerender; try multiple times
  let tries = 0;
  const t = setInterval(() => {
    tries++;
    addBtn();
    if(document.getElementById("vsp-btn-releases") || tries >= 25) clearInterval(t);
  }, 400);

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", addBtn);
  else addBtn();
})();
'''.strip("\n") + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8", errors="replace")
print("[OK] appended:", MARK, "file=", js_path)
PY

node --check "$pick" >/dev/null 2>&1 && echo "[OK] node --check: syntax OK"
grep -n "VSP_P2_RELEASES_BUTTON_RUNS_V1B" "$pick" | head -n 1 && echo "[OK] marker present"
echo "[OK] patched file: $pick"
