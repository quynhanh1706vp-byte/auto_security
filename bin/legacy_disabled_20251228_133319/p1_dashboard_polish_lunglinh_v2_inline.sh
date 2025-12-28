#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

cp -f "$TPL" "${TPL}.bak_polish_v2_${TS}"
echo "[BACKUP] ${TPL}.bak_polish_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

tpl = Path("templates/vsp_dashboard_2025.html")
s = tpl.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_DASHBOARD_POLISH_LUNGLINH_V2_INLINE"
if MARK in s:
    print("[OK] marker exists, skip")
    raise SystemExit(0)

inject = textwrap.dedent(r"""
<!-- VSP_P1_DASHBOARD_POLISH_LUNGLINH_V2_INLINE -->
<style>
:root{
  --vsp-bg:#070e1a;
  --vsp-panel: rgba(12,18,33,.72);
  --vsp-border: rgba(120,140,170,.16);
  --vsp-text: rgba(232,238,255,.92);
  --vsp-muted: rgba(200,212,240,.60);
  --vsp-shadow: 0 10px 30px rgba(0,0,0,.30);
}
html,body{ background:var(--vsp-bg)!important; color:var(--vsp-text)!important; }

/* widen + center content (kill "biển trống") */
main, .main, #main, .container, .page, .vsp-page, #app, .app{
  max-width:1320px !important;
  margin:0 auto !important;
}
main, .main, #main, .container, .page, .vsp-page{
  padding:14px 16px !important;
}

/* premium cards */
.card, .panel, [class*="card"], [class*="panel"]{
  border-radius:16px !important;
  border:1px solid var(--vsp-border)!important;
  background:var(--vsp-panel)!important;
  box-shadow:var(--vsp-shadow)!important;
  backdrop-filter: blur(8px);
}

/* buttons */
button, .btn, a.btn, [class*="btn"]{
  border-radius:999px !important;
  border:1px solid rgba(130,160,200,.20)!important;
}
button:hover, .btn:hover, a.btn:hover{
  border-color: rgba(170,210,255,.35)!important;
}

/* mute debug-ish look */
.small, .muted, [class*="muted"]{ color:var(--vsp-muted)!important; }

/* hard hide (class-based) */
.vsp-debug, .vsp-debug-box, .vsp-contract, .vsp-hint, .vsp-fetch,
.vsp-legacy-killed, .vsp-legacy-hide{ display:none !important; }
</style>

<script>
(()=>{ try{
  // Make sure we can SEE that polish is loaded
  console.log("[VSP][POLISH] v2 inline loaded");

  const NEEDLES = [
    "Audit / ISO readiness (quick)",
    "ISO quick hint",
    "Data contract",
    "VSP fetch",
    "mapping requires",
    "placeholder",
  ];

  const killByText = ()=>{
    const nodes = document.querySelectorAll("div,section,article,aside");
    let n=0;
    for (const el of nodes){
      if (el.__vsp_polish2_killed) continue;
      const t = (el.innerText||"").trim();
      if (!t) continue;

      // If contains any needle => kill (NO size restriction)
      if (NEEDLES.some(k => t.includes(k))){
        el.__vsp_polish2_killed = true;

        // remove a reasonable container (avoid nuking whole page)
        let r = el;
        for (let i=0;i<8;i++){
          if (!r || !r.parentElement) break;
          const cls = (r.className||"").toString();
          if (cls.includes("card") || cls.includes("panel") || cls.includes("container") || cls.includes("section")) break;
          r = r.parentElement;
        }
        (r||el).classList.add("vsp-debug-box");
        try{ (r||el).remove(); }catch(_){}
        n++;
      }
    }
    if (n) console.log("[VSP][POLISH] removed debug blocks:", n);
  };

  killByText();
  setTimeout(killByText, 300);
  setTimeout(killByText, 900);

  const mo = new MutationObserver(()=>killByText());
  mo.observe(document.documentElement, {subtree:true, childList:true});
}catch(e){ console.log("[VSP][POLISH] error", e); }} )();
</script>
<!-- /VSP_P1_DASHBOARD_POLISH_LUNGLINH_V2_INLINE -->
""").strip()

# Inject right after <head> (guaranteed apply)
s2 = re.sub(r'(<head[^>]*>)', r'\1\n' + inject + "\n", s, count=1, flags=re.I)
tpl.write_text(s2, encoding="utf-8")
print("[OK] patched template inline polish v2")
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Open Console: must see [VSP][POLISH] v2 inline loaded."
