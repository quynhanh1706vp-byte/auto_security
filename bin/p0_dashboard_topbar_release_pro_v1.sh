#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TARGET_JS=""
if [ -f "static/js/vsp_dash_only_v1.js" ]; then
  TARGET_JS="static/js/vsp_dash_only_v1.js"
elif [ -f "static/js/vsp_bundle_commercial_v2.js" ]; then
  TARGET_JS="static/js/vsp_bundle_commercial_v2.js"
else
  TARGET_JS="$(ls -1 static/js/*dash*.js 2>/dev/null | head -n 1 || true)"
fi
[ -n "${TARGET_JS}" ] || { echo "[ERR] cannot find dashboard js"; exit 2; }

cp -f "${TARGET_JS}" "${TARGET_JS}.bak_topbar_${TS}"
echo "[BACKUP] ${TARGET_JS}.bak_topbar_${TS}"

export TARGET_JS
python3 - <<'PY'
from pathlib import Path
import os, textwrap

p = Path(os.environ["TARGET_JS"])
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_DASH_TOPBAR_RELEASE_PRO_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P0_DASH_TOPBAR_RELEASE_PRO_V1 ===================== */
(()=> {
  try{
    const onlyDash = () => (location && location.pathname === "/vsp5");
    if (!onlyDash()) return;

    const css = `
#vsp_cmdbar_v1{
  position:sticky; top:0; z-index:99998;
  margin: 10px 12px 8px 12px;
  padding: 10px 12px;
  border-radius: 16px;
  background: linear-gradient(180deg, rgba(11,18,34,.90), rgba(8,12,24,.86));
  border: 1px solid rgba(255,255,255,.10);
  box-shadow: 0 14px 36px rgba(0,0,0,.45);
  backdrop-filter: blur(7px);
  display:flex; align-items:center; justify-content:space-between; gap:12px;
  font: 12px/1.35 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
  color: rgba(255,255,255,.92);
}
#vsp_cmdbar_v1 .lhs{display:flex; align-items:center; gap:10px; min-width:260px;}
#vsp_cmdbar_v1 .brand{
  font-weight: 900; letter-spacing:.25px; font-size: 13px;
}
#vsp_cmdbar_v1 .chip{
  padding: 4px 8px; border-radius: 999px;
  border:1px solid rgba(255,255,255,.12);
  background: rgba(255,255,255,.05);
  opacity:.95;
}
#vsp_cmdbar_v1 .mid{display:flex; align-items:center; gap:10px; flex:1; justify-content:center; min-width: 320px;}
#vsp_cmdbar_v1 .kv{display:flex; flex-direction:column; gap:2px; min-width: 280px;}
#vsp_cmdbar_v1 .k{opacity:.72; font-size: 11px;}
#vsp_cmdbar_v1 .v{font-weight:800; letter-spacing:.15px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;}
#vsp_cmdbar_v1 .rhs{display:flex; align-items:center; gap:8px;}
#vsp_cmdbar_v1 button{
  cursor:pointer;
  border:1px solid rgba(255,255,255,.14);
  background: rgba(255,255,255,.06);
  color: rgba(255,255,255,.92);
  padding: 8px 10px;
  border-radius: 12px;
  font-weight: 800;
}
#vsp_cmdbar_v1 button:disabled{opacity:.55; cursor:not-allowed;}
#vsp_cmdbar_v1 .dot{
  width:10px; height:10px; border-radius:50%;
  background: rgba(255,255,255,.35);
  box-shadow: 0 0 0 4px rgba(255,255,255,.06);
  margin-right:4px;
}
#vsp_cmdbar_v1 .dot.ok{background:#24d17e; box-shadow:0 0 0 4px rgba(36,209,126,.12);}
#vsp_cmdbar_v1 .dot.warn{background:#f4b400; box-shadow:0 0 0 4px rgba(244,180,0,.12);}
#vsp_cmdbar_v1 .dot.err{background:#ff4d4f; box-shadow:0 0 0 4px rgba(255,77,79,.12);}
#vsp_cmdbar_v1 .mini{opacity:.76; font-weight:700;}
    `.trim();

    const ensureStyle = ()=>{
      if (document.getElementById("vsp_cmdbar_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_cmdbar_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const humanBytes = (n)=>{
      if (!n && n!==0) return "";
      const u=["B","KB","MB","GB","TB"];
      let x=Number(n), i=0;
      while (x>=1024 && i<u.length-1){ x/=1024; i++; }
      return `${x.toFixed(i?1:0)} ${u[i]}`;
    };

    const pickAnchor = ()=>{
      const sels = [
        "#kpiRow",".kpi-row",".kpi-grid",".kpiGrid",
        "#vsp_kpis",".vsp-kpis",".vsp_top_cards",".vsp-top-cards",
        "main",".container",".page"
      ];
      for (const q of sels){
        const el=document.querySelector(q);
        if (el) return el;
      }
      return document.body;
    };

    const render = ()=>{
      if (!onlyDash()) return;
      if (document.getElementById("vsp_cmdbar_v1")) return;

      ensureStyle();

      const bar=document.createElement("div");
      bar.id="vsp_cmdbar_v1";
      bar.innerHTML = `
        <div class="lhs">
          <span class="dot" id="vsp_cmdbar_dot_v1"></span>
          <span class="brand">VSP • Dashboard</span>
          <span class="chip" id="vsp_cmdbar_env_v1">LIVE</span>
          <span class="mini" id="vsp_cmdbar_ts_v1">—</span>
        </div>

        <div class="mid">
          <div class="kv">
            <div class="k">Latest release</div>
            <div class="v" id="vsp_cmdbar_rel_v1">checking…</div>
          </div>
          <div class="kv" style="min-width:220px">
            <div class="k">Artifact</div>
            <div class="v" id="vsp_cmdbar_art_v1">—</div>
          </div>
        </div>

        <div class="rhs">
          <button id="vsp_cmdbar_btn_refresh_v1" title="Refresh release info">Refresh</button>
          <button id="vsp_cmdbar_btn_audit_v1" title="Open audit link (if available)">Audit</button>
          <button id="vsp_cmdbar_btn_dl_v1" title="Download latest package">Download</button>
        </div>
      `;

      // insert near top of dashboard layout
      const anchor = pickAnchor();
      const parent = anchor.parentElement || document.body;
      try{
        parent.insertBefore(bar, anchor);
      }catch(e){
        document.body.prepend(bar);
      }

      const $ = (id)=>document.getElementById(id);
      const dot = $("vsp_cmdbar_dot_v1");
      const rel = $("vsp_cmdbar_rel_v1");
      const art = $("vsp_cmdbar_art_v1");
      const ts  = $("vsp_cmdbar_ts_v1");
      const bR  = $("vsp_cmdbar_btn_refresh_v1");
      const bA  = $("vsp_cmdbar_btn_audit_v1");
      const bD  = $("vsp_cmdbar_btn_dl_v1");

      let last = null;

      const setDot = (mode)=>{
        dot.className = "dot " + (mode||"");
      };

      const tickTs = ()=>{
        const d=new Date();
        ts.textContent = d.toLocaleString();
      };
      tickTs(); setInterval(tickTs, 15000);

      async function load(){
        try{
          setDot("warn");
          rel.textContent = "checking…";
          art.textContent = "—";
          bD.disabled = true; bA.disabled = true;

          const res = await fetch("/api/vsp/release_latest", { cache:"no-store" });
          const j = await res.json();
          last = j;

          if (!j || !j.ok){
            setDot("err");
            rel.textContent = "no release";
            art.textContent = (j && j.err) ? String(j.err) : "—";
            return;
          }

          setDot("ok");

          const pn = j.package_name || "package";
          const sha = (j.sha256 || j.sha || "").toString();
          const shaShort = sha ? (sha.slice(0,8) + "…") : "";
          const size = j.size_bytes || j.size || j.bytes || null;

          rel.textContent = `${pn}${shaShort ? " • " + shaShort : ""}`;
          art.textContent = `${size ? humanBytes(size) : "artifact ready"}${j.release_ts ? " • " + j.release_ts : ""}`;

          bD.disabled = !j.download_url;
          bA.disabled = !j.audit_url;

        }catch(e){
          console.error("[VSP_CMD_BAR_V1] load err", e);
          setDot("err");
          rel.textContent = "error (see console)";
          art.textContent = "release_latest failed";
        }
      }

      bR.addEventListener("click", async ()=>{
        bR.disabled = true;
        try{ await load(); } finally { setTimeout(()=>bR.disabled=false, 450); }
      });

      bD.addEventListener("click", ()=>{
        if (!last || !last.download_url) return;
        window.location.href = last.download_url;
      });

      bA.addEventListener("click", ()=>{
        if (!last || !last.audit_url) return;
        window.open(last.audit_url, "_blank", "noopener,noreferrer");
      });

      // initial + periodic refresh
      load();
      setInterval(()=>{ if (onlyDash()) load(); }, 60000);
    };

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", render, { once:true });
    } else {
      render();
    }

  }catch(e){
    console.error("[VSP_CMD_BAR_V1] fatal", e);
  }
})();
/* ===================== /VSP_P0_DASH_TOPBAR_RELEASE_PRO_V1 ===================== */
""").rstrip() + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK, "to", p)
PY

if command -v node >/dev/null 2>&1; then
  node --check "${TARGET_JS}" >/dev/null && echo "[OK] node --check: ${TARGET_JS}" || echo "[WARN] node --check failed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Open ${BASE}/vsp5 => top command bar appears (Release/Audit/Download/Refresh)."
