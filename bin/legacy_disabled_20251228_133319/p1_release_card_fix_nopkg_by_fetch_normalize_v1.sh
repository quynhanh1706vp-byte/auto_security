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
cp -f "$JS" "${JS}.bak_relfetch_${TS}"
echo "[BACKUP] ${JS}.bak_relfetch_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_FETCH_NORMALIZE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

hook = textwrap.dedent(r"""
/* ===================== VSP_P1_RELEASE_FETCH_NORMALIZE_V1 ===================== */
(()=> {
  if (window.__vsp_p1_release_fetch_norm_v1) return;
  window.__vsp_p1_release_fetch_norm_v1 = true;

  const _fetch = window.fetch;
  if (typeof _fetch !== "function") return;

  function isReleaseLatest(url){
    try{
      const u = String(url||"");
      return u.indexOf("/api/vsp/release_latest") !== -1;
    }catch(e){ return false; }
  }

  window.fetch = async function(input, init){
    const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
    const res = await _fetch.apply(this, arguments);
    try{
      if (!isReleaseLatest(url)) return res;

      // clone + parse json
      const clone = res.clone();
      const j = await clone.json().catch(()=>null);
      if (!j || typeof j !== "object") return res;

      const st = String(j.release_status||"").toUpperCase();
      const ex = (j.release_pkg_exists === true);
      const pkg = (j.release_pkg || j.package || "").toString();

      // Normalize for older UI that expects `package` truthy to show OK
      if ((st === "OK" || ex) && pkg){
        j.ok = true;
        if (!j.package) j.package = pkg;
      }
      // If stale: keep package empty so UI shows STALE/NO PKG
      if (!(st === "OK" || ex)){
        // leave as-is; but ensure ok remains true (endpoint always ok)
        if (typeof j.ok !== "boolean") j.ok = true;
      }

      const body = JSON.stringify(j);
      return new Response(body, {
        status: res.status,
        statusText: res.statusText,
        headers: res.headers
      });
    }catch(e){
      return res;
    }
  };
})();
/* ===================== /VSP_P1_RELEASE_FETCH_NORMALIZE_V1 ===================== */
""")

# append at EOF to avoid breaking bundle execution order
p.write_text(s.rstrip() + "\n\n" + hook + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

# optional syntax check
if command -v node >/dev/null 2>&1; then
  node --check "$JS" || { echo "[ERR] node syntax check failed"; exit 2; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] release fetch normalize installed."
