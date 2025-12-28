#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need python3; need date; need systemctl

JS="static/js/vsp_bundle_commercial_v2.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_releasecard_${TS}"
echo "[BACKUP] ${JS}.bak_releasecard_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RUNS_RELEASE_CARD_V1_SAFEAPPEND"
if MARK in s:
    print("[OK] marker already present")
    raise SystemExit(0)

code = textwrap.dedent(r"""
;(()=> {
  try{
    // ===================== VSP_P1_RUNS_RELEASE_CARD_V1_SAFEAPPEND =====================
    // Runs & Reports only: show Current Release from /out_ci/release_latest.json (no Dashboard touch).
    const isRunsPage = ()=>{
      try{
        const p = (location.pathname||"");
        if (p.includes("vsp5") || p.includes("dashboard")) return false;
        return (p.includes("/runs") || p.includes("runs_reports"));
      }catch(e){ return false; }
    };

    function ensureHost(){
      // Try common containers; otherwise create a safe top panel.
      const sels = [
        "#vsp_runs_root", "#runs_root", "#vsp_tab_root",
        "main", ".container", "body"
      ];
      for (const sel of sels){
        const el = document.querySelector(sel);
        if (el) return el;
      }
      return document.body;
    }

    function upsertCard(html){
      const id = "vsp_current_release_card_v1";
      let box = document.getElementById(id);
      if (!box){
        box = document.createElement("div");
        box.id = id;
        box.style.cssText = [
          "border:1px solid rgba(255,255,255,.12)",
          "background:rgba(10,18,32,.72)",
          "border-radius:14px",
          "padding:12px 14px",
          "margin:10px 0",
          "box-shadow:0 10px 30px rgba(0,0,0,.35)",
          "backdrop-filter: blur(6px)"
        ].join(";");
        const host = ensureHost();
        // If host is body, make it a fixed non-intrusive corner panel
        if (host === document.body){
          box.style.margin = "0";
          box.style.position = "fixed";
          box.style.right = "16px";
          box.style.bottom = "16px";
          box.style.maxWidth = "520px";
          box.style.zIndex = "9999";
          document.body.appendChild(box);
        } else {
          host.insertBefore(box, host.firstChild);
        }
      }
      box.innerHTML = html;
    }

    async function loadRelease(){
      try{
        const r = await fetch("/out_ci/release_latest.json", { credentials:"same-origin", cache:"no-store" });
        if (!r.ok) throw new Error("http_"+r.status);
        const j = await r.json();
        if (!j || !j.package) throw new Error("bad_json");
        const pkg = j.package;
        const sha = j.sha256_file || "";
        const man = j.manifest || "";
        const ts  = j.ts || "";

        const row = (label, val)=> `<div style="display:flex;gap:10px;align-items:baseline;line-height:1.35">
          <div style="min-width:120px;opacity:.78">${label}</div>
          <div style="font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size:12.5px; word-break:break-all">${val}</div>
        </div>`;

        upsertCard(`
          <div style="display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:8px">
            <div style="font-weight:700;letter-spacing:.2px">Current Release</div>
            <div style="opacity:.7;font-size:12px">${ts}</div>
          </div>
          ${row("PACKAGE", `<a href="/${pkg}" style="color:#9ad7ff;text-decoration:none">${pkg}</a>`)}
          ${sha ? row("SHA256", `<a href="/${sha}" style="color:#9ad7ff;text-decoration:none">${sha}</a>`) : ""}
          ${man ? row("MANIFEST", `<a href="/${man}" style="color:#9ad7ff;text-decoration:none">${man}</a>`) : ""}
        `);
      }catch(e){
        // silent (commercial): only show a tiny note if already created
        try{
          upsertCard(`<div style="opacity:.8">Current Release: <span style="opacity:.7">not available</span></div>`);
        }catch(_){}
      }
    }

    const boot = ()=>{
      if (!isRunsPage()) return;
      if (window.__vsp_runs_release_card_v1) return;
      window.__vsp_runs_release_card_v1 = true;
      loadRelease();
      // refresh occasionally (no spam)
      setInterval(()=>{ try{ if (isRunsPage()) loadRelease(); }catch(e){} }, 60000);
    };

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
    else boot();
    // ===================== /VSP_P1_RUNS_RELEASE_CARD_V1_SAFEAPPEND =====================
  }catch(e){}
})();
""").strip("\n") + "\n"

p.write_text(s + ("\n" if not s.endswith("\n") else "") + code, encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[OK] restarted"
