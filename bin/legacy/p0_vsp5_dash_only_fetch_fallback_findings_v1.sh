#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fetch_fallback_${TS}"
echo "[BACKUP] ${JS}.bak_fetch_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DASH_ONLY_FETCH_FALLBACK_FINDINGS_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    s += r"""

/* VSP_P0_DASH_ONLY_FETCH_FALLBACK_FINDINGS_V1 */
(()=> {
  if (window.__vsp_p0_dash_only_fetch_fallback_findings_v1) return;
  window.__vsp_p0_dash_only_fetch_fallback_findings_v1 = true;

  const orig = window.fetch ? window.fetch.bind(window) : null;
  if (!orig) return;

  const shouldHandle = (url)=> (
    typeof url === "string" &&
    url.includes("/api/vsp/run_file_allow") &&
    url.includes("path=findings_unified.json")
  );

  const toReports = (url)=> url.replace("path=findings_unified.json", "path=reports/findings_unified.json");

  window.fetch = async (input, init)=>{
    try{
      const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
      if (!shouldHandle(url)) return orig(input, init);

      // 1st try
      let res = await orig(input, init);
      if (res && res.status === 404) {
        const url2 = toReports(url);
        console.warn("[VSP][DASH_ONLY] findings_unified.json 404 => retry:", url2);
        res = await orig(url2, init);
      }
      return res;
    } catch(e){
      return orig(input, init);
    }
  };

  console.log("[VSP][DASH_ONLY] fetch fallback findings v1 active");
})();
"""
    p.write_text(s, encoding="utf-8")
    print("[OK] appended:", MARK)

# must compile
import subprocess, sys
subprocess.check_call(["node","--check","static/js/vsp_dash_only_v1.js"])
print("[OK] node --check passed")
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R), then click: Load top findings (25)."
