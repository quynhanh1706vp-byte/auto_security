#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_autorefresh_gate_root_${TS}"
echo "[BACKUP] ${JS}.bak_autorefresh_gate_root_${TS}"

python3 - <<'PY'
from pathlib import Path
import time, re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_AUTOREFRESH_GATE_ROOT_CHANGE_V1"
if marker in s:
  print("[SKIP] already patched")
  raise SystemExit(0)

block = r"""
/* VSP_P1_AUTOREFRESH_GATE_ROOT_CHANGE_V1 */
(()=> {
  try{
    if (window.__vsp_p1_autorefresh_gate_root_v1) return;
    window.__vsp_p1_autorefresh_gate_root_v1 = true;

    const POLL_MS = 15000;
    const KEY = "__vsp_last_gate_root_seen_v1";
    const KEY_RELOADED = "__vsp_last_gate_root_reloaded_v1";

    async function fetchRunsMeta(){
      const url = "/api/vsp/runs?_ts=" + Date.now();
      const res = await fetch(url, { cache: "no-store" });
      if (!res.ok) throw new Error("runs meta http " + res.status);
      return await res.json();
    }

    function pickGateRoot(j){
      return (j && (j.rid_latest_gate_root || j.rid_latest || j.rid_last_good || j.rid_latest_findings)) || "";
    }

    async function tick(){
      // chỉ poll khi tab đang active để nhẹ + tránh reload lúc user không xem
      if (document.visibilityState && document.visibilityState !== "visible") return;

      let j;
      try{
        j = await fetchRunsMeta();
      }catch(e){
        console.warn("[VSP][AutoRefresh] runs meta fetch failed", e);
        return;
      }

      const gateRoot = pickGateRoot(j);
      if (!gateRoot) return;

      const lastSeen = sessionStorage.getItem(KEY) || "";
      if (!lastSeen){
        sessionStorage.setItem(KEY, gateRoot);
        console.log("[VSP][AutoRefresh] init gate_root =", gateRoot);
        return;
      }

      if (gateRoot !== lastSeen){
        sessionStorage.setItem(KEY, gateRoot);
        const lastReloaded = sessionStorage.getItem(KEY_RELOADED) || "";
        console.log("[VSP][AutoRefresh] gate_root changed:", lastSeen, "=>", gateRoot);

        // chống loop: chỉ reload 1 lần cho mỗi gateRoot mới
        if (lastReloaded !== gateRoot){
          sessionStorage.setItem(KEY_RELOADED, gateRoot);
          console.log("[VSP][AutoRefresh] reloading to show newest gate_root =", gateRoot);
          setTimeout(()=> { location.reload(); }, 250);
        }
      }
    }

    setInterval(tick, POLL_MS);
    // tick sớm để bắt thay đổi nhanh sau khi run xong
    setTimeout(tick, 1200);
  }catch(e){
    console.warn("[VSP][AutoRefresh] init failed", e);
  }
})();
"""

# chèn block ở cuối file (an toàn nhất)
s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended auto-refresh block")
PY

echo "== node --check =="
node --check static/js/vsp_bundle_commercial_v2.js
echo "[OK] syntax OK"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke HEAD /vsp5 =="
curl -sS -I "$BASE/vsp5" | sed -n '1,12p'
echo "[OK] Open $BASE/vsp5 -> console should show [VSP][AutoRefresh]"
