#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v node >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_reldom_${TS}"
echo "[BACKUP] ${JS}.bak_reldom_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_CARD_DOM_FORCE_FIX_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

hook = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_DOM_FORCE_FIX_V3 ===================== */
(()=> {
  if (window.__vsp_p1_relcard_domfix_v3) return;
  window.__vsp_p1_relcard_domfix_v3 = true;

  const qsa = (sel, root)=>{ try { return Array.from((root||document).querySelectorAll(sel)); } catch(e){ return []; } };
  const qs  = (sel, root)=>{ try { return (root||document).querySelector(sel); } catch(e){ return null; } };
  const txt = (el)=> (el && el.textContent ? el.textContent.trim() : "");

  function findReleaseCard(){
    // heuristic: card contains title "Current Release"
    const nodes = qsa("*");
    for (const n of nodes){
      const t = txt(n);
      if (t === "Current Release") {
        // climb to a container "card"
        let c = n;
        for (let i=0;i<8;i++){
          if (!c) break;
          const buttons = qsa("button", c);
          if (buttons.some(b => txt(b).toLowerCase() === "refresh")) return c;
          c = c.parentElement;
        }
      }
    }
    return null;
  }

  function setBadge(card, status){
    // find badge element near header (often a small pill "NO PKG")
    const pills = qsa("span,div", card).filter(x=>{
      const t = txt(x).toUpperCase();
      return (t === "NO PKG" || t === "STALE" || t === "OK");
    });
    if (pills.length){
      const b = pills[0];
      b.textContent = status;
      // lightweight styling without relying on css classes
      if (status === "OK") {
        b.style.background = "rgba(34,197,94,0.15)";
        b.style.border = "1px solid rgba(34,197,94,0.35)";
        b.style.color = "#86efac";
      } else {
        b.style.background = "rgba(245,158,11,0.12)";
        b.style.border = "1px solid rgba(245,158,11,0.35)";
        b.style.color = "#fcd34d";
      }
      b.style.padding = "2px 8px";
      b.style.borderRadius = "999px";
    }
  }

  function setKV(card, keyLabel, value){
    // card shows rows like: ts / package / sha (left label + right value)
    const rows = qsa("div,span", card);
    for (const r of rows){
      const t = txt(r).toLowerCase();
      if (t === keyLabel){
        // value is usually next sibling
        const v = r.nextElementSibling;
        if (v) v.textContent = value || "-";
      }
    }
  }

  async function refreshCard(card){
    try{
      const res = await fetch("/api/vsp/release_latest", {cache:"no-store"});
      const j = await res.json();
      const ok = (String(j.release_status||"").toUpperCase()==="OK" || j.release_pkg_exists===true);
      const status = ok ? "OK" : "STALE";
      setBadge(card, status);
      setKV(card, "ts", String(j.release_ts||"-"));
      setKV(card, "package", String(j.release_pkg||"-"));
      const sha = String(j.release_sha||"");
      setKV(card, "sha", sha ? sha.slice(0,12) : "-");
    }catch(e){}
  }

  function install(){
    const card = findReleaseCard();
    if (!card) return false;

    // run once now
    refreshCard(card);

    // hook the Refresh button in the card
    const btns = qsa("button", card);
    const rbtn = btns.find(b => txt(b).toLowerCase() === "refresh");
    if (rbtn && !rbtn.__vsp_rel_hooked){
      rbtn.__vsp_rel_hooked = true;
      rbtn.addEventListener("click", ()=> setTimeout(()=> refreshCard(card), 50), true);
    }
    return true;
  }

  // try for a while since card opens as overlay
  let tries = 0;
  const t = setInterval(()=>{
    tries++;
    const ok = install();
    if (ok || tries>=40) clearInterval(t);
  }, 500);

  // observe DOM changes (overlay open/close)
  try{
    const mo = new MutationObserver(()=> { try{ install(); }catch(e){} });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  }catch(e){}
})();
/* ===================== /VSP_P1_RELEASE_CARD_DOM_FORCE_FIX_V3 ===================== */
""")

p.write_text(s.rstrip() + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release card DOM force-fix v3 installed."
