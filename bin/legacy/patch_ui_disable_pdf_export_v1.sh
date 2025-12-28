#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

# pick likely main template(s)
T_CAND=()
if [ -f "templates/vsp_4tabs_commercial_v1.html" ]; then
  T_CAND+=("templates/vsp_4tabs_commercial_v1.html")
fi
while IFS= read -r f; do T_CAND+=("$f"); done < <(grep -RIl "run_export_v3" templates 2>/dev/null | head -n 5 || true)

[ "${#T_CAND[@]}" -gt 0 ] || { echo "[ERR] cannot find template containing run_export_v3 under templates/"; exit 2; }

for T in "${T_CAND[@]}"; do
  [ -f "$T" ] || continue
  if grep -q "VSP_PDF_EXPORT_PROBE_V1" "$T"; then
    echo "[OK] already patched: $T"
    continue
  fi

  TS="$(date +%Y%m%d_%H%M%S)"
  cp -f "$T" "$T.bak_disable_pdf_${TS}"
  echo "[BACKUP] $T.bak_disable_pdf_${TS}"

  cat >> "$T" <<'HTML'

<!-- ---- commercial UX: disable PDF export if backend says unavailable ----  VSP_PDF_EXPORT_PROBE_V1 -->
<style>
  a.vsp-export-disabled, button.vsp-export-disabled {
    opacity: .5 !important;
    cursor: not-allowed !important;
    pointer-events: auto !important;
    text-decoration: none !important;
  }
</style>
<script>
(function(){
  const cache = new Map(); // key: href -> Promise<boolean>
  function parseRidFromHref(href){
    try{
      const u = new URL(href, window.location.origin);
      const m = u.pathname.match(/\/api\/vsp\/run_export_v3\/([^\/?#]+)/);
      if(!m) return null;
      return { rid: m[1], fmt: (u.searchParams.get("fmt")||"").toLowerCase(), url: u.toString() };
    } catch(e){
      return null;
    }
  }
  async function probeAvailable(url){
    if(cache.has(url)) return cache.get(url);
    const p = fetch(url, { method: "HEAD" })
      .then(r => {
        const h = r.headers.get("X-VSP-EXPORT-AVAILABLE");
        if(h === null) return r.ok;
        return h === "1";
      })
      .catch(_ => false);
    cache.set(url, p);
    return p;
  }
  function disableEl(a, reason){
    a.classList.add("vsp-export-disabled");
    a.setAttribute("aria-disabled","true");
    a.setAttribute("title", reason || "PDF export is not available on this build");
    a.addEventListener("click", function(ev){
      ev.preventDefault();
      ev.stopPropagation();
    }, { once: true });
  }

  // Lazily probe on first hover/click (event delegation)
  document.addEventListener("mouseover", async function(ev){
    const a = ev.target.closest && ev.target.closest("a[href*='run_export_v3'][href*='fmt=pdf']");
    if(!a) return;
    const info = parseRidFromHref(a.getAttribute("href"));
    if(!info || info.fmt !== "pdf") return;
    const ok = await probeAvailable(info.url);
    if(!ok) disableEl(a, "PDF export is not available (commercial build: disabled until PDF renderer is installed)");
  }, true);

  document.addEventListener("click", async function(ev){
    const a = ev.target.closest && ev.target.closest("a[href*='run_export_v3'][href*='fmt=pdf']");
    if(!a) return;
    const info = parseRidFromHref(a.getAttribute("href"));
    if(!info || info.fmt !== "pdf") return;
    const ok = await probeAvailable(info.url);
    if(!ok){
      disableEl(a, "PDF export is not available (commercial build: disabled until PDF renderer is installed)");
      ev.preventDefault();
      ev.stopPropagation();
    }
  }, true);
})();
</script>
<!-- ---- end VSP_PDF_EXPORT_PROBE_V1 ---- -->
HTML

  echo "[OK] appended PDF-disable probe to $T"
done

python3 -m py_compile ui/vsp_demo_app.py 2>/dev/null || true
echo "[DONE] patch applied. Hard refresh browser (Ctrl+Shift+R)."
