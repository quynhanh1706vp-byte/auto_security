#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
NEW="static/js/vsp_cio_build_stamp_v1.js"
J1="static/js/vsp_bundle_tabs5_v1.js"
J2="static/js/vsp_tabs4_autorid_v1.js"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need cp; need grep; need sed
command -v node >/dev/null 2>&1 || { echo "[ERR] missing node (need node --check)"; exit 2; }

# 0) backups
for f in "$J1" "$J2"; do
  [ -f "$f" ] || continue
  cp -f "$f" "${f}.bak_buildstamp_${TS}"
done

# 1) write JS (reads build headers from same-origin API response)
cat > "$NEW" <<'JS'
(function(){
  "use strict";
  if (window.__VSP_CIO_BUILD_STAMP_V1) return;
  window.__VSP_CIO_BUILD_STAMP_V1 = true;

  function qs(sel, root){ try{return (root||document).querySelector(sel);}catch(_e){return null;} }
  function ce(tag){ return document.createElement(tag); }
  function txt(s){ return document.createTextNode(String(s||"")); }

  function getRid(){
    try{
      if (window.__vspGetRid) return (window.__vspGetRid()||"").trim();
      return (new URLSearchParams(location.search).get("rid")||"").trim();
    }catch(_e){ return ""; }
  }

  async function fetchBuildHeaders(rid){
    // use an API that already returns X-VSP-RELEASE-* headers in your stack
    const url = "/api/vsp/findings_page_v3?rid=" + encodeURIComponent(rid||"") + "&limit=1&offset=0";
    const r = await fetch(url, { credentials: "same-origin", cache: "no-store" });
    const h = r.headers;
    return {
      rel_ts:  h.get("X-VSP-RELEASE-TS")  || "",
      rel_sha: h.get("X-VSP-RELEASE-SHA") || "",
      rel_pkg: h.get("X-VSP-RELEASE-PKG") || "",
      asset_v: h.get("X-VSP-ASSET-V")     || "",
      code:    r.status
    };
  }

  function shortSha(s){
    s = (s||"").trim();
    return s.length > 12 ? s.slice(0,12) : s;
  }

  function ensureStampHost(){
    // Try common topbar containers; fallback to body
    const host =
      qs("#vsp-topbar") ||
      qs(".vspTopbar") ||
      qs("header") ||
      qs("body");
    if (!host) return null;

    // Avoid duplicates
    if (qs("#vsp-cio-build-stamp")) return qs("#vsp-cio-build-stamp");

    const wrap = ce("div");
    wrap.id = "vsp-cio-build-stamp";
    wrap.style.cssText = [
      "display:flex",
      "align-items:center",
      "gap:10px",
      "margin-left:auto",
      "padding:6px 10px",
      "border-radius:10px",
      "border:1px solid rgba(255,255,255,0.10)",
      "background:rgba(0,0,0,0.25)",
      "font:12px/1.2 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace",
      "color:rgba(255,255,255,0.85)"
    ].join(";");

    const label = ce("span");
    label.id = "vsp-cio-build-text";
    label.appendChild(txt("Build: …"));

    const copy = ce("button");
    copy.type = "button";
    copy.id = "vsp-cio-build-copy";
    copy.textContent = "Copy";
    copy.style.cssText = [
      "cursor:pointer",
      "border-radius:10px",
      "padding:6px 10px",
      "border:1px solid rgba(255,255,255,0.14)",
      "background:rgba(255,255,255,0.06)",
      "color:rgba(255,255,255,0.9)",
      "font:12px ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,'Liberation Mono','Courier New',monospace"
    ].join(";");

    copy.addEventListener("click", async function(){
      try{
        const t = (label.textContent||"").trim();
        await navigator.clipboard.writeText(t);
        copy.textContent = "Copied";
        setTimeout(()=>{ copy.textContent="Copy"; }, 900);
      }catch(_e){
        copy.textContent = "NoClip";
        setTimeout(()=>{ copy.textContent="Copy"; }, 900);
      }
    });

    wrap.appendChild(label);
    wrap.appendChild(copy);

    // Prefer append into topbar row if exists, else host
    try{
      host.appendChild(wrap);
    }catch(_e){
      try{ (document.body||host).appendChild(wrap); }catch(_e2){}
    }
    return wrap;
  }

  async function main(){
    const host = ensureStampHost();
    if (!host) return;

    const label = qs("#vsp-cio-build-text") || host;
    const rid = getRid();

    // show instantly
    label.textContent = "RID: " + (rid || "(none)") + " • Build: …";

    let meta = null;
    try{
      meta = await fetchBuildHeaders(rid);
    }catch(e){
      label.textContent = "RID: " + (rid||"(none)") + " • Build: (api fail)";
      return;
    }

    const parts = [];
    parts.push("RID: " + (rid||"(none)"));
    if (meta.rel_ts)  parts.push("rel=" + meta.rel_ts);
    if (meta.rel_sha) parts.push("sha=" + shortSha(meta.rel_sha));
    if (meta.asset_v) parts.push("asset=" + meta.asset_v);
    if (!meta.rel_ts && !meta.rel_sha && !meta.asset_v) parts.push("code=" + String(meta.code||""));

    label.textContent = parts.join(" • ");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>{ main(); }, { once:true });
  } else {
    main();
  }
})();
JS

node --check "$NEW" >/dev/null
echo "[OK] wrote + syntax OK: $NEW"

# 2) Inject loader into both bundles (idempotent)
inject_loader(){
  local f="$1"
  [ -f "$f" ] || return 0
  if grep -q "VSP_CIO_BUILDSTAMP_V1_LOADER" "$f"; then
    echo "[OK] already injected: $f"
    return 0
  fi
  # prepend safe loader without literal \n issues
  python3 - <<PY
from pathlib import Path
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")
loader = """// VSP_CIO_BUILDSTAMP_V1_LOADER
try{
  if(!document.querySelector('script[data-vsp-cio-buildstamp]')){
    var s=document.createElement('script');
    s.src='/static/js/vsp_cio_build_stamp_v1.js?v='+(window.__VSP_ASSET_V||Date.now());
    s.defer=true;
    s.setAttribute('data-vsp-cio-buildstamp','1');
    document.head.appendChild(s);
  }
}catch(_e){}
"""
p.write_text(loader + "\n" + s, encoding="utf-8")
PY
  node --check "$f" >/dev/null || { echo "[ERR] syntax fail: $f"; exit 2; }
  echo "[PATCH] injected: $f"
}

inject_loader "$J1"
inject_loader "$J2"

echo "[DONE] Build stamp injected. Ctrl+F5 once."
