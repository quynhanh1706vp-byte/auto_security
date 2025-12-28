#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_degraded_${TS}"
echo "[BACKUP] ${JS}.bak_degraded_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_DEGRADED_PANEL_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon=textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_DEGRADED_PANEL_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const TOOLS = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];

    const css = `
#vsp_degraded_v1{
  margin: 10px 12px 10px 12px;
  border-radius: 16px;
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.10);
  box-shadow: 0 14px 36px rgba(0,0,0,.25);
  padding: 10px 12px;
  color: rgba(255,255,255,.92);
  font: 12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
}
#vsp_degraded_v1 .row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
#vsp_degraded_v1 .ttl{font-weight:900;letter-spacing:.2px}
#vsp_degraded_v1 .muted{opacity:.72}
#vsp_degraded_v1 .pill{
  display:inline-flex;align-items:center;gap:6px;
  padding:4px 8px;border-radius:999px;
  border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.05);
  font-weight:900;
}
#vsp_degraded_v1 .pill .d{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.35);box-shadow:0 0 0 3px rgba(255,255,255,.06)}
#vsp_degraded_v1 .pill.ok .d{background:#24d17e; box-shadow:0 0 0 3px rgba(36,209,126,.12)}
#vsp_degraded_v1 .pill.warn .d{background:#f4b400; box-shadow:0 0 0 3px rgba(244,180,0,.12)}
#vsp_degraded_v1 .pill.err .d{background:#ff4d4f; box-shadow:0 0 0 3px rgba(255,77,79,.12)}
#vsp_degraded_v1 table{width:100%; border-collapse:collapse; margin-top:8px}
#vsp_degraded_v1 th, #vsp_degraded_v1 td{padding:8px; border-top:1px solid rgba(255,255,255,.08); vertical-align:top}
#vsp_degraded_v1 th{opacity:.72; text-align:left; font-weight:900}
#vsp_degraded_v1 a{
  color:rgba(255,255,255,.90);
  text-decoration:none;
  border-bottom:1px dashed rgba(255,255,255,.22);
}
#vsp_degraded_v1 a:hover{border-bottom-color:rgba(255,255,255,.55)}
    `.trim();

    const ensureStyle=()=>{
      if (document.getElementById("vsp_degraded_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_degraded_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const isRid=(v)=>{
      if (!v) return false;
      v=String(v).trim();
      if (v.length<6||v.length>80) return false;
      if (/\s/.test(v)) return false;
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]+$/.test(v)) return false;
      if (!/\d/.test(v)) return false;
      return true;
    };

    const getRid=()=>{
      const v=(window.__vsp_last_rid_v1||"").trim();
      return isRid(v)?v:"";
    };

    const runFileUrl=(rid, path)=>`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;

    const pickAnchor=()=>{
      // try to place after cmdbar or after gate story panel if exists
      const gs = document.getElementById("vsp_gatestory_v1");
      if (gs) return gs;
      const cmd = document.getElementById("vsp_cmdbar_v1");
      if (cmd) return cmd;
      return document.body;
    };

    const ensurePanel=()=>{
      ensureStyle();
      if (document.getElementById("vsp_degraded_v1")) return document.getElementById("vsp_degraded_v1");
      const a = pickAnchor();
      const p = document.createElement("div");
      p.id="vsp_degraded_v1";
      p.innerHTML = `
        <div class="row">
          <div class="ttl">Degraded / Missing tools</div>
          <span class="pill warn" id="vsp_deg_pill_v1"><span class="d"></span><span id="vsp_deg_txt_v1">checking…</span></span>
          <span class="muted" id="vsp_deg_rid_v1"></span>
        </div>
        <div class="muted" id="vsp_deg_hint_v1" style="margin-top:6px">
          Shows why a run is DEGRADED (timeouts/missing tools) — CIO-friendly.
        </div>
        <div id="vsp_deg_tbl_wrap_v1"></div>
      `;
      a.insertAdjacentElement("afterend", p);
      return p;
    };

    const setPill=(mode, text)=>{
      const pill=document.getElementById("vsp_deg_pill_v1");
      const txt=document.getElementById("vsp_deg_txt_v1");
      if (!pill || !txt) return;
      pill.classList.remove("ok","warn","err");
      pill.classList.add(mode||"warn");
      txt.textContent=text||"—";
    };

    const toolStatus=(o)=>{
      if (!o || typeof o !== "object") return {cls:"err", st:"UNKNOWN", why:"no data"};
      if (o.missing || o.is_missing) return {cls:"err", st:"MISSING", why:(o.reason||o.err||o.message||"missing")};
      if (o.degraded || o.is_degraded || o.status==="degraded") return {cls:"warn", st:"DEGRADED", why:(o.reason||o.err||o.message||"degraded")};
      if (o.ok === true || o.status==="ok") return {cls:"ok", st:"OK", why:(o.reason||"")};
      return {cls:"warn", st:String(o.status||"WARN").toUpperCase(), why:(o.reason||o.err||"")};
    };

    const guessSummaryPath=(tool)=>{
      const t=tool.toLowerCase();
      if (t==="codeql") return "codeql_summary.json";
      return `${t}_summary.json`;
    };

    const guessLogPaths=(tool)=>{
      const t=tool.toLowerCase();
      // best-effort: these may or may not exist; open in new tab if allowed by allowlist
      const cands = [];
      if (t==="kics") cands.push("kics/kics.log","kics.log");
      if (t==="codeql") cands.push("codeql/codeql.log","codeql.log");
      if (t==="semgrep") cands.push("semgrep/semgrep.log","semgrep.log");
      if (t==="trivy") cands.push("trivy/trivy.log","trivy.log");
      if (t==="gitleaks") cands.push("gitleaks/gitleaks.log","gitleaks.log");
      if (t==="syft") cands.push("syft/syft.log","syft.log");
      if (t==="grype") cands.push("grype/grype.log","grype.log");
      if (t==="bandit") cands.push("bandit/bandit.log","bandit.log");
      return cands;
    };

    const fetchGateSummary=async(rid)=>{
      const u = runFileUrl(rid, "run_gate_summary.json");
      const r = await fetch(u, {cache:"no-store"});
      return await r.json();
    };

    const openFirstAvailable = async (rid, paths)=>{
      for (const path of paths){
        const u = runFileUrl(rid, path);
        // best-effort HEAD by fetch (may still return 200 with ok=false; accept)
        try{
          const r = await fetch(u, {cache:"no-store"});
          if (r && r.status === 200){
            window.open(u, "_blank", "noopener,noreferrer");
            return true;
          }
        }catch(e){}
      }
      // fallback: open first
      const u0 = runFileUrl(rid, paths[0] || "");
      window.open(u0, "_blank", "noopener,noreferrer");
      return false;
    };

    let lastRid="";

    const render = async ()=>{
      const rid=getRid();
      const panel=ensurePanel();
      const ridEl=document.getElementById("vsp_deg_rid_v1");
      if (ridEl) ridEl.textContent = rid ? `RID: ${rid}` : "RID: —";

      if (!rid){
        setPill("warn","RID not ready");
        const w=document.getElementById("vsp_deg_tbl_wrap_v1");
        if (w) w.innerHTML = `<div class="muted" style="margin-top:8px">Bấm Refresh/Pin RID để có dữ liệu.</div>`;
        return;
      }

      let gs=null;
      try{ gs = await fetchGateSummary(rid); }catch(e){}

      const by = (gs && (gs.by_tool || gs.tools || gs.byTool)) || {};
      const rows = [];

      for (const tool of TOOLS){
        const obj = (()=> {
          const tl = tool.toLowerCase();
          for (const k of Object.keys(by||{})){
            if (k.toLowerCase() === tl) return by[k];
          }
          return by[tool] || null;
        })();

        const st = toolStatus(obj);
        if (st.cls === "ok") continue; // only show problem tools
        rows.push({tool, st});
      }

      if (!rows.length){
        setPill("ok","No degraded/missing tools");
        const w=document.getElementById("vsp_deg_tbl_wrap_v1");
        if (w) w.innerHTML = `<div class="muted" style="margin-top:8px">All 8 tools reported OK (or no degraded flags).</div>`;
        return;
      }

      const hasMissing = rows.some(r=>r.st.st==="MISSING");
      setPill(hasMissing ? "err" : "warn", hasMissing ? "Missing tools detected" : "Degraded tools detected");

      const w=document.getElementById("vsp_deg_tbl_wrap_v1");
      if (!w) return;

      const htmlRows = rows.map(r=>{
        const summaryPath = guessSummaryPath(r.tool);
        const sumUrl = runFileUrl(rid, summaryPath);
        return `
          <tr>
            <td><span class="pill ${r.st.cls}"><span class="d"></span><span>${r.tool}</span></span></td>
            <td><b>${r.st.st}</b><div class="muted" style="margin-top:4px">${String(r.st.why||"").slice(0,220)}</div></td>
            <td>
              <div><a href="${sumUrl}" target="_blank" rel="noopener noreferrer">summary</a> <span class="muted">(${summaryPath})</span></div>
              <div style="margin-top:6px"><a href="#" data-tool="${r.tool}">open log</a> <span class="muted">(best-effort)</span></div>
            </td>
          </tr>
        `;
      }).join("");

      w.innerHTML = `
        <table>
          <thead><tr><th style="width:170px">Tool</th><th>Status / reason</th><th style="width:240px">Links</th></tr></thead>
          <tbody>${htmlRows}</tbody>
        </table>
      `;

      // bind open log handlers
      w.querySelectorAll('a[data-tool]').forEach(a=>{
        a.addEventListener("click",(e)=>{
          e.preventDefault();
          const tool = a.getAttribute("data-tool") || "";
          const paths = guessLogPaths(tool);
          if (paths.length) openFirstAvailable(rid, paths);
        });
      });

      // if RID changed, re-render quickly once to catch updated gate_summary
      if (rid !== lastRid){
        lastRid = rid;
        setTimeout(()=>render(), 1200);
      }
    };

    const boot=()=>{
      if (!(location && location.pathname==="/vsp5")) return;
      let n=0;
      const t=setInterval(()=>{
        n++;
        if (document.getElementById("vsp_cmdbar_v1")){
          clearInterval(t);
          render();
          setInterval(render, 60000); // align with your auto-refresh
        }
        if (n>120) clearInterval(t);
      }, 250);
    };

    if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_DEGRADED_PANEL_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_DEGRADED_PANEL_V1 ===================== */
""").rstrip()+"\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Degraded/Missing panel appears with per-tool links."
