#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_toollane_dedupe_${TS}"
echo "[BACKUP] ${JS}.bak_toollane_dedupe_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_DASH_ONLY_TOOLLANE_DEDUPE_V1"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    patch = textwrap.dedent(r"""
    /* VSP_P0_DASH_ONLY_TOOLLANE_DEDUPE_V1
       Hide legacy/duplicate tool lane blocks (UNKNOWN-heavy / "Derived from run_gate_summary.json")
       so only the hardened 8-tool lane remains visible.
    */
    (()=> {
      if (window.__vsp_p0_dash_only_toollane_dedupe_v1) return;
      window.__vsp_p0_dash_only_toollane_dedupe_v1 = true;

      const toolsRe = /(Semgrep|Gitleaks|KICS|Trivy|Syft|Grype|Bandit|CodeQL)/i;

      function isInsideNewLane(el){
        try{
          return !!(el && (el.id === "vsp_dash_only_toollane_host_v1"
                    || el.closest?.("#vsp_dash_only_toollane_host_v1")
                    || el.querySelector?.("#vsp_dash_only_toollane_grid_v1")));
        }catch(e){ return false; }
      }

      function hideNode(node, why){
        try{
          if (!node || isInsideNewLane(node)) return false;
          node.style.display = "none";
          node.setAttribute("data-vsp-hide", why || "legacy");
          return true;
        }catch(e){ return false; }
      }

      function hideLegacyOnce(){
        let hid = 0;

        // 1) Blocks around "Derived from run_gate_summary.json"
        const leaves = Array.from(document.querySelectorAll("*")).filter(el => el && el.children && el.children.length === 0);
        for (const el of leaves){
          const tx = (el.textContent || "").trim();
          if (!/Derived from run_gate_summary\.json/i.test(tx)) continue;

          // walk up until a container that looks like the legacy tool lane (has tools + UNKNOWN)
          let cur = el.parentElement;
          for (let i=0; i<10 && cur; i++){
            const t = cur.textContent || "";
            const unknownCnt = (t.match(/UNKNOWN/g) || []).length;
            if (toolsRe.test(t) && unknownCnt >= 1 && !isInsideNewLane(cur)){
              if (hideNode(cur, "legacy-toollane-derived")) hid++;
              break;
            }
            cur = cur.parentElement;
          }
        }

        // 2) UNKNOWN-heavy blocks that contain tool names (but NOT our new lane)
        const divs = Array.from(document.querySelectorAll("div"));
        for (const d of divs){
          if (!d || isInsideNewLane(d)) continue;
          const t = d.textContent || "";
          const unknownCnt = (t.match(/UNKNOWN/g) || []).length;
          if (unknownCnt >= 2 && toolsRe.test(t)){
            // extra safety: avoid hiding big page containers
            const len = t.length;
            if (len < 2200){
              if (hideNode(d, "unknown-heavy")) hid++;
            }
          }
        }

        return hid;
      }

      // run a few times to catch late renders
      let tries = 0;
      const timer = setInterval(()=> {
        tries++;
        const hid = hideLegacyOnce();
        if (hid > 0) console.log("[VSP][DASH_ONLY] dedupe hid blocks:", hid);
        if (tries >= 8) clearInterval(timer);
      }, 700);

      // also run once after a short delay
      setTimeout(()=> hideLegacyOnce(), 1200);

      console.log("[VSP][DASH_ONLY] toollane dedupe v1 active");
    })();
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + patch, encoding="utf-8")
    print("[OK] appended:", MARK)
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: ONLY one Tool lane (8 tools), no duplicate UNKNOWN lane."
