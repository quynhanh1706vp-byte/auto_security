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
cp -f "$JS" "${JS}.bak_trimfix_v2_${TS}"
echo "[BACKUP] ${JS}.bak_trimfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) JS has no strip(); replace safely
s = s.replace(".strip()", ".trim()").replace(".strip(", ".trim(")

marker = "VSP_P0_DASH_ONLY_FIX_TRIM_AND_MISSING_TOOLS_V2"

if marker not in s:
    block = "/* " + marker + " */\n" + textwrap.dedent(r"""
    (()=> {
      if (window.__vsp_dash_fix_trim_missing_v2) return;
      window.__vsp_dash_fix_trim_missing_v2 = true;

      const CANON = [
        {key:"SEMGREP",  label:"Semgrep"},
        {key:"GITLEAKS", label:"Gitleaks"},
        {key:"KICS",     label:"KICS"},
        {key:"TRIVY",    label:"Trivy"},
        {key:"SYFT",     label:"Syft"},
        {key:"GRYPE",    label:"Grype"},
        {key:"BANDIT",   label:"Bandit"},
        {key:"CODEQL",   label:"CodeQL"},
      ];

      function normVerdict(v){
        let x = "";
        try {
          if (v && typeof v === "object") x = (v.verdict || v.status || v.state || v.result || "");
          else x = (v || "");
        } catch(e){ x = ""; }
        x = (x == null ? "" : (""+x)).toUpperCase().trim();
        if (!x) return "UNKNOWN";
        if (x === "OK") return "GREEN";
        if (x === "FAIL") return "RED";
        if (x === "WARN" || x === "WARNING") return "AMBER";
        return x;
      }

      function pillLabel(v){
        const x = normVerdict(v);
        if (x === "GREEN") return "OK";
        if (x === "RED") return "FAIL";
        if (x === "AMBER") return "AMBER";
        if (x === "MISSING") return "MISSING";
        return "UNKNOWN";
      }

      function findToolCard(label){
        // Try multiple heuristics: card contains tool label text
        const nodes = Array.from(document.querySelectorAll("div,section,article,li"));
        label = (label || "").toLowerCase();
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (!t) continue;
          // Must contain tool name and be "card-like" (has border/padding or inside tool lane)
          if (t.includes(label)) {
            // avoid huge containers: prefer smaller nodes
            if (t.length < 220) return n;
          }
        }
        return null;
      }

      function setCardStatus(card, statusText){
        if (!card) return;
        // If card already has a clear status line, update it; else append a status line.
        const st = (statusText || "UNKNOWN").toUpperCase().trim();
        // try find a child that looks like status
        const kids = Array.from(card.querySelectorAll("div,span,p,small"));
        let target = null;
        for (const k of kids){
          const tx = (k.textContent || "").toUpperCase().trim();
          if (tx === "OK" || tx === "FAIL" || tx === "AMBER" || tx === "MISSING" || tx === "UNKNOWN" || tx === "[OBJECT OBJECT]"){
            target = k; break;
          }
        }
        if (!target){
          // pick last child text node-ish
          target = kids.length ? kids[kids.length - 1] : null;
        }
        if (target){
          target.textContent = st;
        } else {
          const d = document.createElement("div");
          d.textContent = st;
          d.style.opacity = "0.85";
          d.style.marginTop = "6px";
          card.appendChild(d);
        }
        // add a css-ish class for visual
        card.classList.remove("ok","fail","amber","missing","unknown");
        if (st==="OK") card.classList.add("ok");
        else if (st==="FAIL") card.classList.add("fail");
        else if (st==="AMBER") card.classList.add("amber");
        else if (st==="MISSING") card.classList.add("missing");
        else card.classList.add("unknown");
      }

      async function fetchJSON(url){
        const r = await fetch(url, {cache:"no-store"});
        if (!r.ok) throw new Error("HTTP "+r.status);
        return await r.json();
      }

      async function refreshFromGateSummary(){
        try {
          const latest = await fetchJSON("/api/vsp/rid_latest_gate_root");
          if (!latest || !latest.ok || !latest.rid) return;
          const rid = latest.rid;

          const gs = await fetchJSON("/api/vsp/run_file_allow?rid=" + encodeURIComponent(rid) + "&path=run_gate_summary.json");
          const byTool = (gs && gs.by_tool && typeof gs.by_tool === "object") ? gs.by_tool : {};

          // update 8 tools; missing -> MISSING
          for (const t of CANON){
            const v = byTool[t.key];
            const verdict = v ? normVerdict(v) : "MISSING";
            const pill = pillLabel(verdict === "MISSING" ? "MISSING" : verdict);
            const card = findToolCard(t.label) || findToolCard(t.key) || null;
            setCardStatus(card, pill);
          }

          // store for other code
          window.__vsp_gate_summary = gs;
        } catch(e){
          console.warn("[VSP][DASH_ONLY] gate_summary refresh failed:", e && e.message ? e.message : e);
        }
      }

      // run once + interval
      setTimeout(refreshFromGateSummary, 250);
      setInterval(refreshFromGateSummary, 4000);
      console.log("[VSP][DASH_ONLY] trim+missing-tools fixer v2 active");
    })();
    """).lstrip()
    s += "\n\n" + block

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_dash_only_v1.js:", marker)
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Expect: no strip() error; missing tools show MISSING."
