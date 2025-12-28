#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_bindrid_${TS}"
echo "[BACKUP] ${F}.bak_bindrid_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_REPORT_BINDRID_DOM_REWRITE_P0PLUS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = r'''
/* VSP_REPORT_BINDRID_DOM_REWRITE_P0PLUS_V1 */
(function(){
  function extractRidFromContext(el){
    if (!el) return null;
    // 1) dataset
    if (el.dataset){
      if (el.dataset.rid) return el.dataset.rid;
      if (el.dataset.runId) return el.dataset.runId;
      if (el.dataset.runid) return el.dataset.runid;
    }
    // 2) row text scan
    const tr = el.closest ? el.closest("tr") : null;
    const txt = (tr && (tr.innerText || tr.textContent)) ? (tr.innerText || tr.textContent) : (el.innerText || el.textContent || "");
    const m = txt.match(/RUN_[A-Za-z0-9:_-]+/);
    return m ? m[0] : null;
  }

  function toRunFileUrl(rid, name){
    const clean = (name || "").replace(/^\/+/, "");
    const leaf = clean.replace(/^api\/reports\//, "").replace(/^\/?api\/reports\//, "");
    const n = ("reports/" + leaf.replace(/^reports\//, "")).replace(/\/+/g, "/");
    return "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent(n);
  }

  function rewriteLinks(root){
    root = root || document;
    const as = root.querySelectorAll ? root.querySelectorAll('a[href*="/api/reports/"], a[href^="/api/reports/"]') : [];
    as.forEach(a => {
      try{
        const href = a.getAttribute("href") || "";
        if (!href.includes("/api/reports/")) return;
        if (href.includes("/api/vsp/run_file?rid=")) return; // already ok
        const rid = extractRidFromContext(a);
        if (!rid) return;

        // parse name after /api/reports/
        const idx = href.indexOf("/api/reports/");
        const tail = href.slice(idx + "/api/reports/".length).split("?")[0].split("#")[0];
        a.setAttribute("href", toRunFileUrl(rid, tail));
        a.setAttribute("data-bindrid", "1");
      }catch(e){}
    });
  }

  function kick(){
    rewriteLinks(document);
    setTimeout(() => rewriteLinks(document), 250);
    setTimeout(() => rewriteLinks(document), 1200);
  }

  // Observe dynamic re-render (filters, pagination, reload)
  const obs = new MutationObserver(() => rewriteLinks(document));
  obs.observe(document.documentElement, {subtree:true, childList:true});

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", kick);
  } else {
    kick();
  }
})();
'''.lstrip("\n")

# append at end (safe, idempotent via MARK)
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_runs_tab_resolved_v1.js >/dev/null 2>&1 && echo "[OK] node --check OK" || { echo "[ERR] node --check failed"; exit 3; }
fi

echo "[NEXT] restart UI + hard refresh (Ctrl+F5)"
