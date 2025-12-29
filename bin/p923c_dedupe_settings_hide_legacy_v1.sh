#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_c_settings_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need curl; need date
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p923c_${TS}"
echo "[OK] backup => ${F}.bak_p923c_${TS}"

python3 - <<'PY'
from pathlib import Path
import datetime

F = Path("static/js/vsp_c_settings_v1.js")
s = F.read_text(encoding="utf-8", errors="replace")
tag = "P923C_DEDUPE_HIDE_LEGACY_SETTINGS_V1"
if tag in s:
    print("[OK] already patched:", tag)
    raise SystemExit(0)

ins = r"""
// P923C_DEDUPE_HIDE_LEGACY_SETTINGS_V1
(function(){
  function _normTxt(t){ return String(t||"").replace(/\s+/g," ").trim(); }

  function vspHideLegacySettings(root){
    try{
      if(!root || !root.nodeType) return;
      const markers = [
        "Settings - Commercial Playbook",
        "8-tool suite",
        "Endpoint probes",
        "Ops Status",
        "Severity normalization",
        "ISO 27001 mapping"
      ];

      // Find ONE best legacy container OUTSIDE new root (avoid nuking top bars)
      const nodes = Array.from(document.querySelectorAll("main,section,div"))
        .filter(el => el && el.nodeType===1 && !root.contains(el));

      let best=null, bestScore=0;
      for(const el of nodes){
        const t = _normTxt(el.textContent||"");
        if(!t || t.length < 200 || t.length > 120000) continue;

        let hits=0;
        for(const m of markers){ if(t.indexOf(m) !== -1) hits++; }
        if(hits < 2) continue;

        // prefer “card-like” blocks: not whole body, not too tiny
        const score = hits*1000000 + t.length;
        if(score > bestScore){
          bestScore = score;
          best = el;
        }
      }

      if(best){
        best.style.display = "none";
        best.setAttribute("data-vsp-hidden", "legacy-settings");
        console.log("[P923C] legacy settings block hidden");
      }
    }catch(e){
      console.warn("[P923C] dedupe failed:", e);
    }
  }

  // run after DOM ready + after our root exists
  function kick(){
    const root = document.getElementById("vsp_settings_root")
      || document.querySelector("[data-vsp-settings-root]")
      || document.querySelector("#vsp_settings_app")
      || null;
    if(root) vspHideLegacySettings(root);
  }

  if(document.readyState === "loading"){
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(kick, 80));
  }else{
    setTimeout(kick, 80);
  }
})();
"""

idx = s.rfind("})();")
if idx < 0:
    raise SystemExit("[ERR] cannot find IIFE end '})();' to inject patch")

s2 = s[:idx] + ins + "\n" + s[idx:]
F.write_text(s2, encoding="utf-8")
print("[OK] injected dedupe block =>", tag)
PY

echo "== [P923C] node --check =="
node --check "$F"
echo "[OK] js syntax OK"

echo "== [P923C] restart =="
sudo systemctl restart "$SVC" >/dev/null 2>&1 || true

echo "== [P923C] wait ready =="
for i in $(seq 1 30); do
  code="$(curl -sS --noproxy '*' -o /dev/null -w "%{http_code}" --connect-timeout 1 --max-time 2 "$BASE/api/vsp/healthz" || true)"
  echo "try#$i code=$code"
  [ "$code" = "200" ] && break
  sleep 1
done

echo "== [P923C] smoke =="
bash bin/p918_p0_smoke_no_error_v1.sh

echo "== DONE. Open: $BASE/c/settings (Ctrl+Shift+R) and confirm NO duplicate Settings blocks. =="
