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
cp -f "$JS" "${JS}.bak_outci_hook_${TS}"
echo "[BACKUP] ${JS}.bak_outci_hook_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_runs_quick_actions_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_RELEASE_OUTCI_CLICK_REWRITE_V1"
if marker in s:
    print("[OK] already present:", marker)
else:
    block = textwrap.dedent(r"""
    /* VSP_P1_RELEASE_OUTCI_CLICK_REWRITE_V1
     * Rewrite any click to /out_ci/releases/*.tgz -> /api/vsp/release_pkg_download?path=out_ci/releases/*.tgz
     */
    (()=> {
      try {
        if (window.__vsp_release_outci_click_rewrite_v1) return;
        window.__vsp_release_outci_click_rewrite_v1 = true;

        function toDlUrl(href){
          try{
            const u = new URL(href, location.origin);
            const path = u.pathname || "";
            const m = path.match(/\/out_ci\/releases\/([^\/]+\.tgz)$/i);
            if (!m) return null;
            const rel = "out_ci/releases/" + m[1];
            return location.origin + "/api/vsp/release_pkg_download?path=" + encodeURIComponent(rel);
          }catch(e){ return null; }
        }

        document.addEventListener("click", (ev) => {
          const a = ev.target && ev.target.closest ? ev.target.closest("a") : null;
          if (!a) return;
          const href = a.getAttribute("href") || "";
          if (!href) return;
          const dl = toDlUrl(href);
          if (!dl) return;
          ev.preventDefault();
          ev.stopPropagation();
          window.open(dl, "_blank", "noopener");
          console.log("[ReleaseOutCIRewriteV1] redirected to download endpoint:", dl);
        }, true);

        console.log("[ReleaseOutCIRewriteV1] installed");
      } catch(e) {
        // no-op
      }
    })();
    """).strip() + "\n"

    p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
    print("[OK] appended", marker)

PY

node --check "$JS" >/dev/null 2>&1 && echo "== node check: OK ==" || true
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hook installed. Hard-refresh /runs (Ctrl+Shift+R)."
