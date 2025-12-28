#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_counts_only_msg_${TS}"
echo "[BACKUP] ${JS}.bak_counts_only_msg_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_TOPFIND_COUNTS_ONLY_MSG_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block=textwrap.dedent(r"""
    /* VSP_P0_TOPFIND_COUNTS_ONLY_MSG_V1
       If top_findings API returns ok:false => show clear message (not stuck loading).
    */
    (()=> {
      if (window.__vsp_topfind_counts_only_msg_v1) return;
      window.__vsp_topfind_counts_only_msg_v1 = true;

      function findTopCard(){
        const nodes = Array.from(document.querySelectorAll("div,section,article"));
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (t.includes("top findings")) return n;
        }
        return null;
      }
      function setStatus(msg){
        const card = findTopCard();
        if (!card) return;
        const cells = Array.from(card.querySelectorAll("td,div,span,p"));
        for (const c of cells){
          const t = (c.textContent || "").toLowerCase().trim();
          if (t === "not loaded" || t === "loading..." || t === "loading…" || t.startsWith("load failed") || t.startsWith("loaded:")){
            c.textContent = msg;
            return;
          }
        }
      }

      // Hook fetch to detect ok:false from our endpoints and update UI status
      const _fetch = window.fetch;
      window.fetch = async (...args)=> {
        const res = await _fetch(...args);
        try{
          const url = String(args[0]||"");
          if (url.includes("/api/vsp/top_findings_v1") || url.includes("/api/vsp/top_findings_v2") || url.includes("/api/vsp/top_findings_v3")){
            const clone = res.clone();
            const j = await clone.json().catch(()=>null);
            if (j && j.ok === false){
              setStatus("No detailed findings saved for this run (counts-only). Re-run pipeline with raw findings export enabled.");
            }
          }
        }catch(_){}
        return res;
      };
    })();
    """)
    p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] HARD refresh /vsp5. Now button will show a clear reason instead of 'đơ'."
