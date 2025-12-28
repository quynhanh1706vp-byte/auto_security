#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_toollane_harden_${TS}"
echo "[BACKUP] ${JS}.bak_toollane_harden_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DASH_ONLY_TOOLLANE_HARDEN_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    patch = textwrap.dedent(r"""
    /* VSP_P0_DASH_ONLY_TOOLLANE_HARDEN_V1
       - Capture run_gate_summary.json via fetch wrapper
       - Re-render Tool Lane (8 tools) deterministically
       - Missing tools => MISSING (never UNKNOWN/[object Object])
    */
    (()=> {
      if (window.__vsp_p0_dash_only_toollane_harden_v1) return;
      window.__vsp_p0_dash_only_toollane_harden_v1 = true;

      const TOOLS = ["SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","BANDIT","CODEQL"];
      const LABEL = { SEMGREP:"Semgrep", GITLEAKS:"Gitleaks", KICS:"KICS", TRIVY:"Trivy", SYFT:"Syft", GRYPE:"Grype", BANDIT:"Bandit", CODEQL:"CodeQL" };

      function upper(x){ return (typeof x === "string") ? x.toUpperCase() : ""; }

      function normVerdict(v){
        if (!v) return "MISSING";
        if (typeof v === "string") return upper(v) || "UNKNOWN";
        if (typeof v === "object") {
          if (typeof v.verdict === "string") return upper(v.verdict) || "UNKNOWN";
          if (typeof v.status  === "string") return upper(v.status)  || "UNKNOWN";
          if (typeof v.state   === "string") return upper(v.state)   || "UNKNOWN";
          if (typeof v.result  === "string") return upper(v.result)  || "UNKNOWN";
          // object but no known keys => treat as UNKNOWN, but never print object
          return "UNKNOWN";
        }
        return "UNKNOWN";
      }

      function byToolFrom(gs){
        if (!gs || typeof gs !== "object") return {};
        return gs.by_tool || gs.byTool || gs.by_tools || {};
      }

      function findHeaderNode(){
        // find leaf node whose text matches "Tool lane (8 tools)"
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT, {
          acceptNode(node){
            try{
              if (!node || node.children?.length) return NodeFilter.FILTER_SKIP;
              const t = (node.textContent||"").trim();
              if (/^Tool\s*lane\s*\(\s*8\s*tools\s*\)/i.test(t)) return NodeFilter.FILTER_ACCEPT;
            }catch(e){}
            return NodeFilter.FILTER_SKIP;
          }
        });
        return walker.nextNode();
      }

      function badgeStyle(verdict){
        const v = upper(verdict);
        // minimal styling (dark theme friendly)
        const base = "display:flex;align-items:center;justify-content:space-between;gap:10px;padding:10px 12px;border-radius:12px;border:1px solid rgba(255,255,255,0.06);background:rgba(255,255,255,0.02);";
        let pill = "padding:2px 8px;border-radius:999px;font-size:12px;border:1px solid rgba(255,255,255,0.10);opacity:0.95;";
        if (v === "GREEN" || v === "OK") pill += "background:rgba(16,185,129,0.12);";
        else if (v === "AMBER" || v === "WARN") pill += "background:rgba(245,158,11,0.12);";
        else if (v === "RED" || v === "FAIL") pill += "background:rgba(239,68,68,0.12);";
        else if (v === "MISSING") pill += "background:rgba(148,163,184,0.10);";
        else pill += "background:rgba(99,102,241,0.10);";
        return { base, pill };
      }

      function renderLane(gs){
        const by = byToolFrom(gs);
        const items = TOOLS.map(t=>{
          const raw = by[t] ?? by[t.toLowerCase()] ?? null;
          const verdict = normVerdict(raw);
          return { tool: t, label: LABEL[t] || t, verdict };
        });

        const html = items.map(it=>{
          const st = badgeStyle(it.verdict);
          return `
            <div style="${st.base}">
              <div style="font-weight:600;letter-spacing:0.2px;">${it.label}</div>
              <div style="${st.pill}">${it.verdict}</div>
            </div>
          `;
        }).join("");

        return `
          <div id="vsp_dash_only_toollane_grid_v1"
               style="display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:10px;">
            ${html}
          </div>
        `;
      }

      function applyToolLane(gs){
        const header = findHeaderNode();
        if (!header) return false;
        const hostId = "vsp_dash_only_toollane_host_v1";
        let host = document.getElementById(hostId);
        if (!host){
          host = document.createElement("div");
          host.id = hostId;
          // insert right after the header node
          header.insertAdjacentElement("afterend", host);
        }
        host.innerHTML = renderLane(gs);
        return true;
      }

      async function forceFetchGateSummary(){
        try{
          const r1 = await window.fetch("/api/vsp/rid_latest_gate_root");
          const j1 = await r1.json();
          const rid = j1 && j1.rid;
          if (!rid) return;
          const url = "/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json";
          const r2 = await window.fetch(url);
          const gs = await r2.json();
          window.__vsp_dash_only_last_gate_summary = gs;
          applyToolLane(gs);
        }catch(e){
          console.warn("[VSP][DASH_ONLY] toollane harden forceFetch failed", e);
        }
      }

      function captureFromFetch(url, resp){
        try{
          if (!url || typeof url !== "string") return;
          if (url.indexOf("run_gate_summary.json") === -1) return;
          resp.clone().json().then(gs=>{
            window.__vsp_dash_only_last_gate_summary = gs;
            applyToolLane(gs);
          }).catch(()=>{});
        }catch(e){}
      }

      // Wrap fetch once
      try{
        const orig = window.fetch;
        if (typeof orig === "function" && !orig.__vsp_toollane_harden_wrapped){
          const wrapped = function(input, init){
            const url = (typeof input === "string") ? input : (input && input.url) || "";
            return orig(input, init).then(resp=>{
              captureFromFetch(url, resp);
              return resp;
            });
          };
          wrapped.__vsp_toollane_harden_wrapped = true;
          window.fetch = wrapped;
        }
      }catch(e){}

      // Kick once after load
      setTimeout(()=> {
        if (window.__vsp_dash_only_last_gate_summary) {
          applyToolLane(window.__vsp_dash_only_last_gate_summary);
        } else {
          forceFetchGateSummary();
        }
      }, 900);

      console.log("[VSP][DASH_ONLY] toollane harden v1 active");
    })();
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + patch, encoding="utf-8")
    print("[OK] appended:", MARK)

PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Tool lane should be stable (8 tools) + missing tools => MISSING."
