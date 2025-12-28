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
cp -f "$JS" "${JS}.bak_trimfix_${TS}"
echo "[BACKUP] ${JS}.bak_trimfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# 1) JS: strip() -> trim()
if ".strip(" in s:
  s2 = s.replace(".strip()", ".trim()").replace(".strip(", ".trim(")
  s = s2

# 2) Force 8-tool lane: missing -> MISSING (not UNKNOWN)
marker = "VSP_P0_DASH_ONLY_MISSING_TOOLS_V1"
if marker not in s:
  s += "\n" + textwrap.dedent(rf"""
  /* {marker} */
  (()=>{{
    if (window.__vsp_dash_only_missing_tools_v1) return;
    window.__vsp_dash_only_missing_tools_v1 = true;

    const CANON = ["SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","BANDIT","CODEQL"];

    function normalizeByTool(byTool){{
      const bt = (byTool && typeof byTool === "object") ? byTool : {{}};
      const out = {{}};
      for (const k of CANON){{
        const v = bt[k];
        if (v && typeof v === "object") {{
          const verdict = (v.verdict || v.status || v.state || v.result || "").toString().toUpperCase();
          const total = (typeof v.total === "number") ? v.total : (typeof v.count === "number" ? v.count : undefined);
          out[k] = {{ verdict: verdict || "UNKNOWN", total }};
        }} else {{
          out[k] = {{ verdict: "MISSING" }};
        }}
      }}
      return out;
    }}

    // Hook: whenever a gate_summary object is present on window, normalize it.
    // We keep it non-invasive: if your main code sets window.__vsp_gate_summary, we rewrite by_tool.
    const tryNormalize = ()=>{{
      const gs = window.__vsp_gate_summary || window.vsp_gate_summary || null;
      if (!gs || typeof gs !== "object") return false;
      if (!gs.by_tool || typeof gs.by_tool !== "object") gs.by_tool = {{}};
      gs.by_tool = normalizeByTool(gs.by_tool);
      return true;
    }};

    // Patch render path: if a tools box exists, render 8 tool cards from normalized data.
    function renderToolsBox(gs){{
      const toolsBox = document.querySelector("#tools_box") || document.querySelector("[data-vsp='tools_box']") || document.querySelector(".tool-lane");
      if (!toolsBox || !gs) return;
      const bt = normalizeByTool(gs.by_tool || {{}});
      const pill = (v)=> {{
        const x=(v||"UNKNOWN").toUpperCase();
        if (x==="GREEN"||x==="OK") return "OK";
        if (x==="RED"||x==="FAIL") return "FAIL";
        if (x==="AMBER"||x==="WARN"||x==="WARNING") return "AMBER";
        if (x==="MISSING") return "MISSING";
        return "UNKNOWN";
      }};
      // Only re-render when looks wrong
      const bad = toolsBox.textContent.includes("[object Object]") || toolsBox.textContent.includes("UNKNOWN");
      if (!bad && toolsBox.querySelectorAll(".vsp-toolcard").length>=6) return;

      toolsBox.innerHTML = CANON.map(k=>{{
        const st = pill((bt[k]||{{}}).verdict);
        const cls = st==="OK" ? "ok" : (st==="FAIL" ? "fail" : (st==="AMBER" ? "amber" : (st==="MISSING" ? "missing" : "unknown")));
        return `<div class="vsp-toolcard ${cls}" style="padding:10px;border-radius:12px;background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.06)">
          <div style="font-weight:700;letter-spacing:.2px">${{k}}</div>
          <div style="opacity:.8;margin-top:4px">${{st}}</div>
        </div>`;
      }}).join("");
      toolsBox.style.display="grid";
      toolsBox.style.gridTemplateColumns="repeat(4, minmax(160px, 1fr))";
      toolsBox.style.gap="10px";
    }}

    // Periodic gentle fix (dash-only is light; 1.2s is fine)
    setInterval(()=>{{
      if (tryNormalize()) {{
        const gs = window.__vsp_gate_summary || window.vsp_gate_summary || null;
        renderToolsBox(gs);
      }}
    }}, 1200);

    // Also try once after load
    setTimeout(()=>{{
      tryNormalize();
      const gs = window.__vsp_gate_summary || window.vsp_gate_summary || null;
      renderToolsBox(gs);
    }}, 300);
  }})();
  """).strip() + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched strip->trim and missing-tools normalizer")
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Console should no longer show strip() error; missing tools should show MISSING."
