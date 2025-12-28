#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_TOP_FINDINGS_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_${TS}"

python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, textwrap

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P3_TOP_FINDINGS_V1 ===================== */
(function(){
  try{
    if (window.__VSP_TOP_FINDINGS_V1__) return;
    window.__VSP_TOP_FINDINGS_V1__ = true;

    const SEV_ORDER = { "CRITICAL": 6, "HIGH": 5, "MEDIUM": 4, "LOW": 3, "INFO": 2, "TRACE": 1 };

    function qp(name){
      try { return new URL(location.href).searchParams.get(name) || ""; }
      catch(e){ return ""; }
    }
    function lsGet(k){
      try { return localStorage.getItem(k) || ""; } catch(e){ return ""; }
    }
    async function fetchJson(url){
      const r = await fetch(url, { credentials: "same-origin" });
      if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
      return await r.json();
    }
    function esc(s){
      return (s==null ? "" : String(s))
        .replaceAll("&","&amp;").replaceAll("<","&lt;")
        .replaceAll(">","&gt;").replaceAll('"',"&quot;")
        .replaceAll("'","&#39;");
    }
    function clip(s){
      try { return (s.length > 80) ? (s.slice(0,77)+"…") : s; } catch(e){ return ""; }
    }
    function sevScore(sev){
      const k = (sev||"").toUpperCase();
      return SEV_ORDER[k] || 0;
    }

    function panelCss(){
      return [
        "margin:12px 0 0 0",
        "padding:12px 12px",
        "border:1px solid rgba(255,255,255,0.10)",
        "border-radius:14px",
        "background:rgba(20,22,28,0.72)",
        "backdrop-filter:blur(6px)",
        "color:#eaeaea"
      ].join(";");
    }
    function headCss(){
      return "display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:10px;";
    }
    function btnCss(){
      return [
        "padding:7px 10px",
        "border-radius:10px",
        "border:1px solid rgba(255,255,255,0.14)",
        "background:rgba(10,12,16,0.85)",
        "color:#eaeaea",
        "cursor:pointer",
        "font-size:12px"
      ].join(";");
    }
    function badgeCss(sev){
      const k=(sev||"").toUpperCase();
      // no explicit colors (keep safe), just weight/border
      return "display:inline-block;padding:2px 8px;border-radius:999px;border:1px solid rgba(255,255,255,0.18);font-weight:700;font-size:11px;letter-spacing:0.2px;";
    }
    function rowCss(){
      return "display:grid;grid-template-columns:90px 90px 1fr;gap:10px;align-items:start;padding:8px 0;border-top:1px solid rgba(255,255,255,0.08);";
    }
    function monoCss(){ return "font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;font-size:12px;opacity:0.92;"; }
    function dimCss(){ return "font-size:12px;opacity:0.80;"; }

    function ensurePanel(){
      // Prefer to mount right under run picker bar if exists
      const picker = document.getElementById("vsp-run-picker-bar");
      const root = document.getElementById("vsp5_root") || document.body;

      if (document.getElementById("vsp-top-findings-panel")) return true;

      const host = (picker && picker.parentElement) ? picker.parentElement : root;

      const panel = document.createElement("div");
      panel.id = "vsp-top-findings-panel";
      panel.setAttribute("data-marker", "VSP_P3_TOP_FINDINGS_V1");
      panel.style.cssText = panelCss();
      panel.innerHTML = `
        <div style="${headCss()}">
          <div>
            <div style="font-weight:800;">Top Findings</div>
            <div id="vsp-topfind-sub" style="${dimCss()}">Loading CRITICAL/HIGH…</div>
          </div>
          <div style="display:flex;gap:8px;flex-wrap:wrap;justify-content:flex-end;">
            <a id="vsp-topfind-open-ds" href="/data_source" style="text-decoration:none;">
              <button type="button" style="${btnCss()}">Open Data Source</button>
            </a>
            <button type="button" id="vsp-topfind-copy-filter" style="${btnCss()}">Copy filter</button>
          </div>
        </div>
        <div id="vsp-topfind-list"></div>
      `;

      // insert after picker if exists, else top of host
      if (picker && picker.parentElement === host){
        host.insertBefore(panel, picker.nextSibling);
      } else {
        host.insertBefore(panel, host.firstChild);
      }
      return true;
    }

    async function resolveRid(){
      const rid = qp("rid") || lsGet("vsp_rid_selected");
      if (rid) return rid;
      try{
        const j = await fetchJson("/api/vsp/rid_latest");
        return (j && j.rid) || "";
      }catch(e){
        return "";
      }
    }

    function normalizeFindings(j){
      // expected: { ok:true, from:"...", findings:[...] }
      const arr = (j && (j.findings || j.items || j.data)) || [];
      return Array.isArray(arr) ? arr : [];
    }

    function toRowHtml(f){
      const sev = (f && (f.severity || f.sev)) || "";
      const tool = (f && (f.tool || f.source || f.engine)) || "";
      const file = (f && (f.file || f.path || f.location)) || "";
      const title = (f && (f.title || f.message || f.rule || f.id)) || "";
      const cwe = (f && (f.cwe)) || "";
      const extra = cwe ? (" • CWE " + cwe) : "";

      return `
        <div style="${rowCss()}" class="vsp-topfind-row">
          <div><span style="${badgeCss(sev)}">${esc((sev||"").toUpperCase())}</span></div>
          <div style="${monoCss()}">${esc(clip(tool||"-"))}</div>
          <div>
            <div style="font-weight:700;line-height:1.25;">${esc(title||"-")}</div>
            <div style="${dimCss()}">${esc(clip(file||"-"))}${esc(extra)}</div>
          </div>
        </div>
      `;
    }

    async function loadTopFindings(){
      if (!ensurePanel()) return;

      const sub = document.getElementById("vsp-topfind-sub");
      const list = document.getElementById("vsp-topfind-list");
      const btnCopy = document.getElementById("vsp-topfind-copy-filter");
      const aOpen = document.getElementById("vsp-topfind-open-ds");

      const rid = await resolveRid();
      if (!rid){
        if (sub) sub.textContent = "No RID available (rid_latest failed).";
        return;
      }

      // Deep link attempt (safe even if DS ignores params)
      if (aOpen) aOpen.href = "/data_source?rid=" + encodeURIComponent(rid) + "&sev=" + encodeURIComponent("CRITICAL,HIGH");

      const filterObj = { rid, severities:["CRITICAL","HIGH"], top_n:10, sort:"severity_desc" };

      if (btnCopy){
        btnCopy.onclick = async () => {
          const payload = JSON.stringify(filterObj);
          try{
            await navigator.clipboard.writeText(payload);
            if (sub) sub.textContent = "Copied filter JSON to clipboard.";
          }catch(e){
            // fallback prompt
            try{ window.prompt("Copy filter JSON:", payload); }catch(_){}
          }
        };
      }

      if (sub) sub.textContent = "RID: " + rid + " • loading findings…";

      // Fetch limited findings (enough to pick top CRITICAL/HIGH)
      let findings = [];
      const paths = [
        "reports/findings_unified.json",
        "findings_unified.json"
      ];
      let lastErr = "";
      for (const path of paths){
        try{
          const url = "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=" + encodeURIComponent(path) + "&limit=800";
          const j = await fetchJson(url);
          findings = normalizeFindings(j);
          if (findings.length) break;
        }catch(e){
          lastErr = (e && e.message) ? e.message : String(e);
        }
      }

      if (!findings || !findings.length){
        if (sub) sub.textContent = "RID: " + rid + " • no findings (or failed to load). " + (lastErr ? ("("+lastErr+")") : "");
        if (list) list.innerHTML = `<div style="${dimCss()}">No findings available for CRITICAL/HIGH.</div>`;
        return;
      }

      const picked = findings
        .filter(f => {
          const sev = String((f && (f.severity||f.sev)) || "").toUpperCase();
          return sev === "CRITICAL" || sev === "HIGH";
        })
        .sort((a,b) => sevScore((b && b.severity)||"") - sevScore((a && a.severity)||""))
        .slice(0, 10);

      if (sub) sub.textContent = "RID: " + rid + " • showing " + picked.length + " CRITICAL/HIGH";
      if (list) list.innerHTML = picked.map(toRowHtml).join("") || `<div style="${dimCss()}">No CRITICAL/HIGH found.</div>`;
    }

    function boot(){
      if (document.readyState === "loading"){
        document.addEventListener("DOMContentLoaded", boot, { once:true });
        return;
      }
      loadTopFindings();
    }

    boot();
  }catch(e){
    try{ console.warn("[TopFindingsV1] init error:", e); }catch(_){}
  }
})();
/* ===================== /VSP_P3_TOP_FINDINGS_V1 ===================== */
""").strip("\n") + "\n"

p.write_text(s.rstrip("\n") + "\n\n" + block, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] marker in JS =="
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing in JS"; exit 2; }

echo "== [verify] /vsp5 still loads luxe js =="
curl -fsS "$BASE/vsp5" | grep -q "vsp_dashboard_luxe_v1.js" && echo "[OK] vsp5 loads luxe js" || { echo "[ERR] vsp5 missing luxe js"; exit 2; }

echo "[DONE] Top Findings panel installed. Open: $BASE/vsp5"
