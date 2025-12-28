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

cp -f "$JS" "${JS}.bak_hotfix_deg_${TS}"
echo "[BACKUP] ${JS}.bak_hotfix_deg_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

start = "/* ===================== VSP_P1_DASH_DEGRADED_PANEL_V1 ===================== */"
end   = "/* ===================== /VSP_P1_DASH_DEGRADED_PANEL_V1 ===================== */"
i = s.find(start)
j = s.find(end)

if i == -1 or j == -1 or j < i:
    raise SystemExit("[ERR] cannot find degraded panel marker block to replace")

j2 = j + len(end)

fixed = textwrap.dedent(r"""
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

    const getPinnedRid=()=>{
      const keys=["vsp5_pin_rid","vsp_pin_rid","VSP_PIN_RID","vsp5.rid.pinned","vsp5_last_rid","vsp_last_rid"];
      for (const k of keys){
        try{
          const v=(localStorage.getItem(k)||"").trim();
          if (isRid(v)) return v;
        }catch(e){}
      }
      return "";
    };

    const getRid=()=>{
      const pin=getPinnedRid();
      if (isRid(pin)) return pin;
      const v=(window.__vsp_last_rid_v1||"").trim();
      return isRid(v)?v:"";
    };

    const runFileUrl=(rid, path)=>`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;

    const pickAnchor=()=>{
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
          <span class="pill ok" id="vsp_deg_pill_v1"><span class="d"></span><span id="vsp_deg_txt_v1">OK</span></span>
          <span class="muted" id="vsp_deg_rid_v1"></span>
        </div>
        <div class="muted" id="vsp_deg_hint_v1" style="margin-top:6px">
          Commercial-safe: only raises flags when run is DEGRADED or tools are explicitly missing/degraded.
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

    const toolStatusSafe=(o)=>{
      if (!o || typeof o !== "object") return {cls:"unk", st:"UNKNOWN", why:"no data"};

      if (o.missing || o.is_missing) return {cls:"err", st:"MISSING", why:(o.reason||o.err||o.message||"missing")};
      if (o.degraded || o.is_degraded || o.status==="degraded") return {cls:"warn", st:"DEGRADED", why:(o.reason||o.err||o.message||"degraded")};

      // strong OK signals
      if (o.ok === true || o.status==="ok") return {cls:"ok", st:"OK", why:(o.reason||"")};

      // common summary shape: counts => treat OK
      const hasCounts = !!(o.counts_total || o.counts_by_severity || (o.meta && o.meta.counts_by_severity));
      const hasTotals = (o.findings_count != null) || (o.total_findings != null) || (o.total != null);
      if (hasCounts || hasTotals) return {cls:"ok", st:"OK", why:""};

      // explicit error hint
      if (o.err || o.error || o.message) return {cls:"warn", st:"WARN", why:(o.err||o.error||o.message||"warn")};

      return {cls:"unk", st:"UNKNOWN", why:""};
    };

    const guessSummaryPath=(tool)=>{
      const t=tool.toLowerCase();
      if (t==="codeql") return "codeql_summary.json";
      return `${t}_summary.json`;
    };

    const guessLogPaths=(tool)=>{
      const t=tool.toLowerCase();
      const cands=[];
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
        try{
          const r = await fetch(u, {cache:"no-store"});
          if (r && r.status === 200){
            window.open(u, "_blank", "noopener,noreferrer");
            return true;
          }
        }catch(e){}
      }
      const u0 = runFileUrl(rid, paths[0] || "");
      window.open(u0, "_blank", "noopener,noreferrer");
      return false;
    };

    let lastRid="";

    const render = async ()=>{
      const rid=getRid();
      ensurePanel();

      const ridEl=document.getElementById("vsp_deg_rid_v1");
      if (ridEl) ridEl.textContent = rid ? `RID: ${rid}` : "RID: —";

      const w=document.getElementById("vsp_deg_tbl_wrap_v1");
      if (!rid){
        setPill("warn","RID not ready");
        if (w) w.innerHTML = `<div class="muted" style="margin-top:8px">Bấm Refresh/Pin RID để có dữ liệu.</div>`;
        return;
      }

      let gs=null;
      try{ gs = await fetchGateSummary(rid); }catch(e){}

      const runDegraded = !!(gs && (gs.degraded || gs.is_degraded || (gs.gate && gs.gate.degraded)));

      const by = (gs && (gs.by_tool || gs.tools || gs.byTool)) || {};
      const rows=[];

      for (const tool of TOOLS){
        const obj = (()=> {
          const tl = tool.toLowerCase();
          for (const k of Object.keys(by||{})){
            if (k.toLowerCase() === tl) return by[k];
          }
          return by[tool] || null;
        })();

        const st = toolStatusSafe(obj);
        const explicitBad = (st.cls === "err" || st.st === "DEGRADED");
        const showWhenDegraded = runDegraded && (st.cls === "warn" || st.cls === "unk" || st.st === "WARN" || st.st === "UNKNOWN");

        if (explicitBad || showWhenDegraded){
          rows.push({tool, st});
        }
      }

      if (!runDegraded && !rows.length){
        setPill("ok","No degraded/missing");
        if (w) w.innerHTML = `<div class="muted" style="margin-top:8px">Run is not degraded. Panel stays quiet (commercial-safe).</div>`;
        return;
      }

      if (runDegraded && !rows.length){
        setPill("warn","Degraded (no detail)");
        if (w) w.innerHTML = `<div class="muted" style="margin-top:8px">Run marked degraded but by_tool has no details.</div>`;
        return;
      }

      const hasMissing = rows.some(r=>r.st.st==="MISSING");
      setPill(hasMissing ? "err" : "warn", hasMissing ? "Missing tools" : "Degraded tools");

      const htmlRows = rows.map(r=>{
        const summaryPath = guessSummaryPath(r.tool);
        const sumUrl = runFileUrl(rid, summaryPath);
        const why = String(r.st.why||"").slice(0,240);
        const pillClass = (r.st.cls === "err") ? "err" : "warn";
        return `
          <tr>
            <td><span class="pill ${pillClass}"><span class="d"></span><span>${r.tool}</span></span></td>
            <td><b>${r.st.st}</b><div class="muted" style="margin-top:4px">${why || ""}</div></td>
            <td>
              <div><a href="${sumUrl}" target="_blank" rel="noopener noreferrer">summary</a> <span class="muted">(${summaryPath})</span></div>
              <div style="margin-top:6px"><a href="#" data-tool="${r.tool}">open log</a> <span class="muted">(best-effort)</span></div>
            </td>
          </tr>
        `;
      }).join("");

      if (w){
        w.innerHTML = `
          <table>
            <thead><tr><th style="width:170px">Tool</th><th>Status / reason</th><th style="width:240px">Links</th></tr></thead>
            <tbody>${htmlRows}</tbody>
          </table>
        `;

        w.querySelectorAll('a[data-tool]').forEach(a=>{
          a.addEventListener("click",(e)=>{
            e.preventDefault();
            const tool = a.getAttribute("data-tool") || "";
            const paths = guessLogPaths(tool);
            if (paths.length) openFirstAvailable(rid, paths);
          });
        });
      }

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
          setInterval(render, 60000);
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

s2 = s[:i] + fixed + s[j2:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced degraded panel block with JS-safe version (no # / no python stub)")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Degraded panel is JS-safe + pinned RID first + commercial-safe display."
