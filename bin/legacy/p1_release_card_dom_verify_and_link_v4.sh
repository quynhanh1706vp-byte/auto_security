#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_reldomv4_${TS}"
echo "[BACKUP] ${JS}.bak_reldomv4_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_CARD_DOM_VERIFY_LINK_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

hook = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_CARD_DOM_VERIFY_LINK_V4 ===================== */
(()=> {
  if (window.__vsp_rel_dom_v4) return;
  window.__vsp_rel_dom_v4 = true;

  const qsa = (sel, root)=>{ try { return Array.from((root||document).querySelectorAll(sel)); } catch(e){ return []; } };
  const txt = (el)=> (el && el.textContent ? el.textContent.trim() : "");

  function findCard(){
    const nodes = qsa("*");
    for (const n of nodes){
      if (txt(n) === "Current Release"){
        let c = n;
        for (let i=0;i<10;i++){
          if (!c) break;
          const btns = qsa("button", c);
          if (btns.some(b => txt(b).toLowerCase() === "refresh") &&
              btns.some(b => txt(b).toLowerCase().includes("copy package")) ) return c;
          c = c.parentElement;
        }
      }
    }
    return null;
  }

  function setBadge(card, t){
    const cand = qsa("span,div", card).find(x=>{
      const v = txt(x).toUpperCase();
      return ["NO PKG","STALE","CHECK","OK"].includes(v);
    });
    if (!cand) return;
    cand.textContent = t;
  }

  function setMsg(card, msg){
    // find footer message line contains '/api/vsp/release_latest' or 'verify package'
    const divs = qsa("div,span", card);
    const m = divs.find(x => {
      const v = txt(x).toLowerCase();
      return v.includes("/api/vsp/release_latest") || v.includes("verify package") || v.includes("cannot verify");
    });
    if (m) m.textContent = msg;
  }

  async function refresh(card){
    try{
      const r = await fetch("/api/vsp/release_latest", {cache:"no-store"});
      const j = await r.json();

      const relPath = (j.release_pkg || j.package || "");
      const pkgUrl  = (j.package_url || "");

      // verify exists via endpoint
      let ex = null;
      if (relPath && relPath.startsWith("out_ci/releases/")){
        const u = "/api/vsp/release_pkg_exists?path=" + encodeURIComponent(relPath);
        const rr = await fetch(u, {cache:"no-store"});
        ex = await rr.json().catch(()=>null);
      }

      if (ex && ex.exists){
        setBadge(card, "OK");
        setMsg(card, "updated: " + (j.ts || j.updated || "") + " • pkg verified");
      } else {
        setBadge(card, "CHECK");
        setMsg(card, "updated: " + (j.ts || j.updated || "") + " • verify package: pending");
      }

      // override "Copy package link" to use package_url (download endpoint), not raw /out_ci/... path
      if (pkgUrl){
        const btn = qsa("button", card).find(b => txt(b).toLowerCase().includes("copy package"));
        if (btn && !btn.__vsp_rel_copy_v4){
          btn.__vsp_rel_copy_v4 = true;
          btn.addEventListener("click", async (ev)=>{
            try{
              ev.preventDefault(); ev.stopPropagation();
              await navigator.clipboard.writeText(pkgUrl);
              setMsg(card, "copied package_url: " + pkgUrl);
            }catch(e){}
          }, true);
        }
      }
    }catch(e){}
  }

  function install(){
    const card = findCard();
    if (!card) return false;
    refresh(card);
    const rbtn = qsa("button", card).find(b => txt(b).toLowerCase() === "refresh");
    if (rbtn && !rbtn.__vsp_rel_refresh_v4){
      rbtn.__vsp_rel_refresh_v4 = true;
      rbtn.addEventListener("click", ()=> setTimeout(()=> refresh(card), 50), true);
    }
    return true;
  }

  let tries = 0;
  const t = setInterval(()=>{ tries++; if (install() || tries>40) clearInterval(t); }, 500);

  try{
    const mo = new MutationObserver(()=>{ try{ install(); }catch(e){} });
    mo.observe(document.documentElement, {childList:true, subtree:true});
  }catch(e){}
})();
/* ===================== /VSP_P1_RELEASE_CARD_DOM_VERIFY_LINK_V4 ===================== */
""")

p.write_text(s.rstrip() + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release card DOM verify+link v4 installed."
