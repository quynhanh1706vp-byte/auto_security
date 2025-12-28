#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

# Prefer dashboard-only JS first, fallback to commercial bundle.
TARGET_JS=""
if [ -f "static/js/vsp_dash_only_v1.js" ]; then
  TARGET_JS="static/js/vsp_dash_only_v1.js"
elif [ -f "static/js/vsp_bundle_commercial_v2.js" ]; then
  TARGET_JS="static/js/vsp_bundle_commercial_v2.js"
else
  # last resort: find a dashboard-ish js
  TARGET_JS="$(ls -1 static/js/*dash*.js 2>/dev/null | head -n 1 || true)"
fi

[ -n "${TARGET_JS}" ] || { echo "[ERR] cannot find dashboard js to patch under static/js"; exit 2; }
[ -f "${TARGET_JS}" ] || { echo "[ERR] not found: ${TARGET_JS}"; exit 2; }

cp -f "${TARGET_JS}" "${TARGET_JS}.bak_releasedl_${TS}"
echo "[BACKUP] ${TARGET_JS}.bak_releasedl_${TS}"

export TARGET_JS
python3 - <<'PY'
from pathlib import Path
import os, textwrap

p = Path(os.environ["TARGET_JS"])
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DASH_RELEASEDL_BTN_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK, "in", p)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P0_DASH_RELEASEDL_BTN_V1 ===================== */
(()=> {
  try{
    const onlyOnDash = () => {
      const pn = (location && location.pathname) ? location.pathname : "";
      // Dashboard route in your UI is /vsp5 (keep it strict to avoid touching other tabs)
      if (pn !== "/vsp5") return false;
      return true;
    };

    const ensure = () => {
      if (!onlyOnDash()) return;
      if (window.__vsp_release_dl_btn_v1) return;
      window.__vsp_release_dl_btn_v1 = true;

      const wrap = document.createElement("div");
      wrap.id = "vsp_release_dl_wrap_v1";
      wrap.style.cssText = [
        "position:fixed",
        "right:16px",
        "bottom:16px",
        "z-index:99999",
        "display:flex",
        "align-items:center",
        "gap:10px",
        "padding:10px 12px",
        "border-radius:14px",
        "background:rgba(10,16,32,.92)",
        "border:1px solid rgba(255,255,255,.10)",
        "box-shadow:0 10px 30px rgba(0,0,0,.45)",
        "backdrop-filter: blur(6px)",
        "font: 12px/1.35 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial",
        "color:rgba(255,255,255,.92)"
      ].join(";");

      const label = document.createElement("div");
      label.innerHTML = `<div style="font-weight:700;letter-spacing:.2px">Release</div>
                         <div id="vsp_release_dl_status_v1" style="opacity:.78;margin-top:2px">ready</div>`;

      const btn = document.createElement("button");
      btn.type = "button";
      btn.id = "vsp_release_dl_btn_v1";
      btn.textContent = "Download latest package";
      btn.style.cssText = [
        "cursor:pointer",
        "border:1px solid rgba(255,255,255,.14)",
        "background:rgba(255,255,255,.06)",
        "color:rgba(255,255,255,.92)",
        "padding:9px 12px",
        "border-radius:12px",
        "font-weight:700",
        "letter-spacing:.15px"
      ].join(";");

      const st = () => document.getElementById("vsp_release_dl_status_v1");
      const setStatus = (t)=>{ const el = st(); if (el) el.textContent = t || ""; };

      async function fetchLatest(){
        setStatus("checking…");
        const res = await fetch("/api/vsp/release_latest", { cache:"no-store" });
        let j = null;
        try{ j = await res.json(); }catch(e){ j = { ok:false, err:"bad json" }; }
        if (!j || !j.ok) {
          setStatus("no release");
          console.warn("[VSP][RELEASEDL_BTN_V1] no release:", j);
          return null;
        }
        setStatus(`ok • ${j.package_name || "package"}`);
        return j;
      }

      btn.addEventListener("click", async ()=>{
        try{
          btn.disabled = true;
          btn.style.opacity = "0.7";
          const j = await fetchLatest();
          const dl = j && j.download_url;
          if (!dl){
            setStatus("missing download_url");
            return;
          }
          setStatus("downloading…");
          window.location.href = dl;
        }catch(e){
          console.error("[VSP][RELEASEDL_BTN_V1] err", e);
          setStatus("error (console)");
        }finally{
          setTimeout(()=>{ btn.disabled = false; btn.style.opacity = "1"; }, 900);
        }
      });

      wrap.appendChild(label);
      wrap.appendChild(btn);
      document.body.appendChild(wrap);

      // prefetch once (non-blocking)
      setTimeout(()=>{ fetchLatest().catch(()=>{}); }, 400);
    };

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", ensure, { once:true });
    } else {
      ensure();
    }
  }catch(e){
    console.error("[VSP][RELEASEDL_BTN_V1] fatal", e);
  }
})();
/* ===================== /VSP_P0_DASH_RELEASEDL_BTN_V1 ===================== */
""").strip() + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK, "to", p)
PY

# optional js syntax check if node exists
if command -v node >/dev/null 2>&1; then
  node --check "${TARGET_JS}" >/dev/null && echo "[OK] node --check: ${TARGET_JS}" || echo "[WARN] node --check failed (still restarted)"
fi

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Open http://127.0.0.1:8910/vsp5 => bottom-right 'Release' box => Download latest package."
