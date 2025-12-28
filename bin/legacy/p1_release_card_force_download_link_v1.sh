#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_runs_quick_actions_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_relpkgdl_${TS}"
echo "[BACKUP] ${JS}.bak_relpkgdl_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_RELEASE_CARD_FORCE_DOWNLOAD_LINK_V1"
if marker in s:
    print("[OK] already present:", marker)
else:
    s += "\n" + textwrap.dedent(r"""
/* VSP_P1_RELEASE_CARD_FORCE_DOWNLOAD_LINK_V1 */
(()=> {
  if (window.__vsp_p1_rel_pkgdl_v1) return;
  window.__vsp_p1_rel_pkgdl_v1 = true;

  const dlUrl = (relPkg) => {
    if (!relPkg) return "";
    const base = location.origin;
    return base + "/api/vsp/release_pkg_download?path=" + encodeURIComponent(String(relPkg));
  };

  async function fetchReleaseLatest(){
    try{
      const r = await fetch("/api/vsp/release_latest", {cache:"no-store"});
      const j = await r.json();
      return j || {};
    }catch(e){
      return {};
    }
  }

  async function copyText(txt){
    try{
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(txt);
        return true;
      }
    }catch(e){}
    try{
      const ta = document.createElement("textarea");
      ta.value = txt; ta.style.position="fixed"; ta.style.left="-9999px";
      document.body.appendChild(ta); ta.focus(); ta.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(ta);
      return !!ok;
    }catch(e){}
    return false;
  }

  function hookOnce(btn){
    if (!btn || btn.dataset.vspRelPkgdlV1 === "1") return;
    btn.dataset.vspRelPkgdlV1 = "1";
    btn.addEventListener("click", async (ev) => {
      try{
        ev.preventDefault(); ev.stopPropagation();
      }catch(e){}
      const meta = await fetchReleaseLatest();
      const relPkg = meta.release_pkg || meta.release_pkg_path || "";
      const url = dlUrl(relPkg);
      if (!url){
        console.warn("[RelPkgDL] no release_pkg in release_latest");
        return;
      }
      const ok = await copyText(url);
      console.log("[RelPkgDL] copy", ok ? "OK" : "FAIL", url);
    }, true);
  }

  function hookPkgLine(root){
    // nếu package line là <a> hoặc element có text giống file tgz => biến nó thành link download
    try{
      const metaPromise = fetchReleaseLatest();
      metaPromise.then(meta=>{
        const relPkg = meta.release_pkg || meta.release_pkg_path || "";
        const url = dlUrl(relPkg);
        if (!url) return;

        const nodes = root.querySelectorAll("a, code, div, span");
        for (const el of nodes){
          const t = (el.textContent || "").trim();
          if (!t) continue;
          if (t.includes("VSP_RELEASE_") && t.endsWith(".tgz")){
            if (el.tagName === "A"){
              el.href = url;
              el.target = "_blank";
            }else{
              el.style.cursor = "pointer";
              if (el.dataset.vspRelPkgNavV1 === "1") continue;
              el.dataset.vspRelPkgNavV1 = "1";
              el.addEventListener("click", (e)=>{
                try{ e.preventDefault(); e.stopPropagation(); }catch(_){}
                window.open(url, "_blank");
              }, true);
            }
            // chỉ cần xử lý 1 chỗ là đủ
            break;
          }
        }
      });
    }catch(e){}
  }

  function scan(){
    // tìm đúng nút theo label
    const btns = Array.from(document.querySelectorAll("button"));
    for (const b of btns){
      const t = (b.textContent || "").trim().toLowerCase();
      if (t === "copy package link" || t.includes("copy package link")){
        hookOnce(b);
      }
    }
    // cố gắng tìm release card container để hook package line
    const cards = Array.from(document.querySelectorAll("div"));
    for (const c of cards){
      const t = (c.textContent || "");
      if (t.includes("Current Release") && t.includes("package")){
        hookPkgLine(c);
      }
    }
  }

  // observer để chịu re-render
  const mo = new MutationObserver(()=> scan());
  mo.observe(document.documentElement, {subtree:true, childList:true});
  setTimeout(scan, 50);
  setTimeout(scan, 500);
  setTimeout(scan, 1500);

  console.log("[RelPkgDL] installed: copy/open package uses /api/vsp/release_pkg_download");
})();
""")
    p.write_text(s, encoding="utf-8")
    print("[OK] appended marker:", marker)
PY

node --check "$JS" >/dev/null 2>&1 && echo "== node check: OK ==" || echo "== node check: (skip/failed) =="

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release card forced to use download endpoint."
echo "NOTE: mở lại tab /runs và hard-refresh (Ctrl+Shift+R) để ăn JS mới."
