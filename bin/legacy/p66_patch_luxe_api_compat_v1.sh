#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p66_${TS}"
echo "[OK] backup ${F}.bak_p66_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_luxe_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "P66_LUXE_API_COMPAT_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

shim = r"""
/* P66_LUXE_API_COMPAT_V1: rewrite legacy API urls to v2 + attach rid when possible */
(function(){
  if (window.__vspFetchCompatPatched) return;
  window.__vspFetchCompatPatched = true;

  function getRid(){
    try{
      const u = new URL(location.href);
      return u.searchParams.get("rid") || u.searchParams.get("run_id") || "";
    }catch(e){ return ""; }
  }

  function normalizeToRel(url){
    try{
      if (typeof url !== "string") return "";
      if (url.startsWith("http://") || url.startsWith("https://")) {
        const u = new URL(url);
        if (u.origin !== location.origin) return url; // cross-origin: don't touch
        return u.pathname + u.search;
      }
      return url;
    }catch(e){ return url; }
  }

  function rewriteRel(url){
    try{
      url = normalizeToRel(url);

      // map old endpoints
      url = url.replace("/api/vsp/top_findings_v1", "/api/vsp/top_findings_v2");
      url = url.replace("/api/vsp/top_findings_v0", "/api/vsp/top_findings_v2");

      // datasource dashboard mode -> datasource?rid=<rid>
      if (url.includes("/api/vsp/datasource") && url.includes("mode=dashboard")) {
        const rid = getRid();
        url = "/api/vsp/datasource" + (rid ? ("?rid="+encodeURIComponent(rid)) : "");
      }

      // if calling datasource without rid, attach rid if we have one
      if (url.startsWith("/api/vsp/datasource") && !url.includes("rid=")) {
        const rid = getRid();
        if (rid) url += (url.includes("?") ? "&" : "?") + "rid=" + encodeURIComponent(rid);
      }

      return url;
    }catch(e){ return url; }
  }

  const _fetch = window.fetch;
  window.fetch = function(input, init){
    try{
      if (typeof input === "string") {
        return _fetch.call(this, rewriteRel(input), init);
      }
      if (input && typeof input === "object" && input.url) {
        const newUrl = rewriteRel(input.url);
        if (typeof newUrl === "string" && newUrl !== input.url) {
          input = new Request(newUrl, input);
        }
      }
    }catch(e){}
    return _fetch.call(this, input, init);
  };
})();
"""

# insert after "use strict" if present, else prepend
m = re.search(r'(?m)^(\"use strict\";|\'use strict\';)\s*', s)
if m:
    idx = m.end()
    s = s[:idx] + "\n" + shim + "\n" + s[idx:]
else:
    s = shim + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] patched", p)
PY

node --check "$F" >/dev/null
echo "[DONE] P66 applied. Hard refresh browser: Ctrl+Shift+R"
