#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_silenceexport_${TS}"
echo "[BACKUP] $F.bak_silenceexport_${TS}"

# idempotent
if grep -q "VSP_SILENCE_EXPORT_HEAD_PROBE_V1" "$F"; then
  echo "[OK] already patched, skip"
  exit 0
fi

cat >> "$F" <<'JS'

/* === VSP_SILENCE_EXPORT_HEAD_PROBE_V1 ===
 * Fix commercial UX: stop console noise caused by HEAD probes to /api/vsp/run_export_v3/*
 * We only intercept HEAD (probe). Real export clicks (usually GET via navigation) are not touched.
 */
(function(){
  try{
    const _fetch = window.fetch ? window.fetch.bind(window) : null;
    if (!_fetch) return;

    window.fetch = function(input, init){
      try{
        const url = String(input || "");
        const method = String((init && init.method) || "GET").toUpperCase();
        if (method === "HEAD" && url.indexOf("/api/vsp/run_export_v3/") >= 0){
          // Return 200 + header available=0 so UI can hide/disable without throwing 404.
          return Promise.resolve(new Response("", {
            status: 200,
            headers: {
              "X-VSP-EXPORT-AVAILABLE": "0",
              "Content-Type": "application/json"
            }
          }));
        }
      }catch(e){}
      return _fetch(input, init);
    };
  }catch(e){}
})();
 /* === /VSP_SILENCE_EXPORT_HEAD_PROBE_V1 === */
JS

echo "[OK] appended export HEAD probe silencer -> $F"
echo "[NEXT] hard refresh browser (Ctrl+Shift+R)"
