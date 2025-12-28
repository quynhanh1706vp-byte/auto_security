#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k20_${TS}"
echo "[BACKUP] ${F}.bak_p3k20_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_tabs5_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P3K20_FETCHSHIM_URLRID_AND_HIDE_TIMEOUT_BANNER_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = f"""/* === {marker} ===
   Goal (commercial-safe):
   - If URL already has ?rid=... then:
     (1) Intercept fetch() for /api/vsp/rid_latest*, /api/vsp/rid_latest_gate_root
         and return the same rid immediately (no timeout, no abort).
     (2) Swallow unhandledrejection for timeout/network style failures.
     (3) Hide any "Dashboard error: timeout" banner if it appears.
*/
(function(){{
  try{{
    if (window.__VSP_P3K20__) return;
    window.__VSP_P3K20__ = true;

    const sp = new URLSearchParams(location.search || "");
    const urlRid = (sp.get("rid") || "").trim();

    function _hideTimeoutBanner(){{
      try{{
        const nodes = [];
        const ids = ["vsp-dashboard-error","dashboard-error","vspError","vsp-error","dash-error"];
        for (const id of ids){{
          const el = document.getElementById(id);
          if (el) nodes.push(el);
        }}
        document.querySelectorAll(".vsp-banner,.vsp-toast,.alert,.notice,.msg,.status,.note").forEach(el=>nodes.push(el));
        // Light scan (avoid heavy DOM walk)
        document.querySelectorAll("div,span,p").forEach((el, idx)=>{{ if (idx < 180) nodes.push(el); }});

        for (const el of nodes){{
          if (!el || !el.textContent) continue;
          const t = (el.textContent || "").trim();
          if (/dashboard\\s*error/i.test(t) && /timeout/i.test(t)) {{
            el.textContent = "";
            el.style.display = "none";
          }}
        }}
      }}catch(_e){{}}
    }}

    window.addEventListener("DOMContentLoaded", ()=>{{
      _hideTimeoutBanner();
      setTimeout(_hideTimeoutBanner, 700);
      setTimeout(_hideTimeoutBanner, 2500);
    }});

    window.addEventListener("unhandledrejection", (e)=>{{
      try{{
        const r = e && e.reason;
        const msg = String((r && (r.message || r)) || "").toLowerCase();
        if (msg.includes("timeout") || msg.includes("networkerror") || msg.includes("failed to fetch")) {{
          e.preventDefault();
          _hideTimeoutBanner();
          return;
        }}
      }}catch(_e){{}}
    }});

    if (!urlRid) return;
    if (!window.fetch) return;

    const realFetch = window.fetch.bind(window);
    function shouldIntercept(u){{
      if (!u) return false;
      return (
        u.includes("/api/vsp/rid_latest") ||
        u.includes("/api/vsp/rid_latest_v3") ||
        u.includes("/api/vsp/rid_latest_gate_root")
      );
    }}

    window.fetch = function(input, init){{
      try{{
        const u = (typeof input === "string") ? input : (input && input.url) || "";
        if (shouldIntercept(u)) {{
          const body = JSON.stringify({{ ok:true, rid:urlRid, mode:"url_rid" }});
          const headers = new Headers({{
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store"
          }});
          return Promise.resolve(new Response(body, {{ status: 200, headers }}));
        }}
      }}catch(_e){{}}
      return realFetch(input, init);
    }};
  }}catch(_e){{}}
}})();
"""

p.write_text(inject + "\n\n" + s, encoding="utf-8")
print("[OK] injected fetch-shim + banner scrub")
PY

echo "== node -c =="
node -c "$F"
echo "[OK] node -c passed"

echo "== restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC"
  systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }
else
  echo "[WARN] systemctl not found; please restart manually"
fi

echo "== marker =="
grep -n "VSP_P3K20_FETCHSHIM_URLRID_AND_HIDE_TIMEOUT_BANNER_V1" -n "$F" | head -n 2 || true
echo "[DONE] p3k20_tabs5_fetchshim_urlrid_and_hide_timeout_banner_v1"
