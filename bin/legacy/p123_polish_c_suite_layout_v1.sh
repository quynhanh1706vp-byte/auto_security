#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p123_${TS}"
echo "[OK] backup: ${F}.bak_p123_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P123_POLISH_CSUITE_LAYOUT_V1"
if MARK in s:
    print("[OK] P123 already present, skip.")
    raise SystemExit(0)

addon = r"""
/* ===== VSP_P123_POLISH_CSUITE_LAYOUT_V1 ===== */
;(function(){
  if (window.__VSP_P123__) return;
  window.__VSP_P123__ = 1;

  function onReady(fn){
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", fn, {once:true});
    else fn();
  }

  function addStyle(id, css){
    if (document.getElementById(id)) return;
    const st = document.createElement("style");
    st.id = id;
    st.textContent = css;
    document.head.appendChild(st);
  }

  function normText(el){
    return (el && el.textContent ? el.textContent.trim().toLowerCase() : "");
  }

  function hideLegacyTables(){
    // Hide tables that look like legacy header tables (only <thead> or very few rows)
    const tables = Array.from(document.querySelectorAll("table"));
    for (const t of tables){
      try{
        const ths = Array.from(t.querySelectorAll("thead th")).map(x=>normText(x)).filter(Boolean);
        const rows = t.querySelectorAll("tbody tr").length;
        const looksLikeLegacyHeader =
          ths.length >= 4 && ths.includes("rid") && (ths.includes("actions") || ths.includes("overall") || ths.includes("summary"));
        if (looksLikeLegacyHeader && rows <= 1){
          t.style.display = "none";
        }
      }catch(_){}
    }
  }

  function decorateActionChips(){
    // Turn all “action” links/buttons into consistent chips (Runs tab is the biggest win)
    const els = Array.from(document.querySelectorAll("a,button"));
    for (const el of els){
      const t = normText(el);
      if (!t) continue;

      const isAction =
        ["dashboard","csv","reports.tgz","reports","sarif","html","summary","use rid","open","sha","refresh","load","save","export","json"].includes(t);

      if (!isAction) continue;

      el.classList.add("vsp-chip");
      if (t === "dashboard") el.classList.add("vsp-chip--primary");
      else if (t === "use rid") el.classList.add("vsp-chip--accent");
      else if (t === "refresh" or t === "load") el.classList.add("vsp-chip--ghost");
      else el.classList.add("vsp-chip--muted");
    }
  }

  function polishTables(){
    // Add classes to big tables to apply zebra/hover/spacing
    const tables = Array.from(document.querySelectorAll("table"));
    for (const t of tables){
      // Skip tiny layout tables (if any)
      const rows = t.querySelectorAll("tr").length;
      if (rows < 3) continue;
      t.classList.add("vsp-table");
    }
  }

  function collapseHugePre(){
    // Collapse very large <pre> blocks (Settings/Rule Overrides raw JSON) into <details>
    const pres = Array.from(document.querySelectorAll("pre"));
    for (const pre of pres){
      try{
        const txt = (pre.textContent || "").trim();
        if (!txt) continue;
        // Heuristic: looks like JSON and is long
        const looksJson = (txt.startswith("{") and txt.endswith("}")) or (txt.startswith("[") and txt.endswith("]"));
        const lines = txt.split("\n").length
        if (!looksJson || lines < 30) continue;

        // avoid double wrap
        if (pre.closest("details")) continue;

        const details = document.createElement("details");
        details.className = "vsp-details";
        details.open = false;

        const sum = document.createElement("summary");
        sum.textContent = "Raw JSON (click to expand)";
        details.appendChild(sum);

        // Keep the pre but constrain height
        pre.classList.add("vsp-pre");
        details.appendChild(pre.cloneNode(true));
        pre.replaceWith(details);
      }catch(_){}
    }
  }

  onReady(function(){
    addStyle("vsp-p123-style", `
      :root{
        --vsp-bg0:#0b1220;
        --vsp-bg1:#0f1a2d;
        --vsp-card:rgba(255,255,255,.035);
        --vsp-card2:rgba(255,255,255,.055);
        --vsp-border:rgba(255,255,255,.08);
        --vsp-border2:rgba(255,255,255,.12);
        --vsp-text:rgba(255,255,255,.86);
        --vsp-text2:rgba(255,255,255,.68);
        --vsp-blue:rgba(96,165,250,.95);
        --vsp-cyan:rgba(34,211,238,.92);
      }

      /* Tables */
      table.vsp-table{
        width:100%;
        border-collapse:separate;
        border-spacing:0;
        background:var(--vsp-card);
        border:1px solid var(--vsp-border);
        border-radius:14px;
        overflow:hidden;
      }
      table.vsp-table thead th{
        text-transform:uppercase;
        letter-spacing:.06em;
        font-size:11px;
        color:var(--vsp-text2);
        background:rgba(255,255,255,.03);
        border-bottom:1px solid var(--vsp-border);
        padding:10px 12px;
      }
      table.vsp-table tbody td{
        padding:10px 12px;
        border-bottom:1px solid rgba(255,255,255,.06);
        color:var(--vsp-text);
        font-size:12px;
      }
      table.vsp-table tbody tr:nth-child(odd){
        background:rgba(255,255,255,.018);
      }
      table.vsp-table tbody tr:hover{
        background:rgba(96,165,250,.08);
      }
      table.vsp-table tbody td:first-child{
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", monospace;
        font-size:11.5px;
        color:rgba(255,255,255,.78);
      }

      /* Chips */
      .vsp-chip{
        display:inline-flex;
        align-items:center;
        justify-content:center;
        gap:6px;
        padding:5px 10px;
        margin-right:8px;
        border-radius:999px;
        border:1px solid var(--vsp-border2);
        background:rgba(255,255,255,.03);
        color:rgba(255,255,255,.86) !important;
        font-size:12px;
        line-height:1;
        text-decoration:none !important;
        cursor:pointer;
        transition:transform .08s ease, background .12s ease, border-color .12s ease;
      }
      .vsp-chip:hover{ transform:translateY(-1px); background:rgba(255,255,255,.06); border-color:rgba(255,255,255,.18); }
      .vsp-chip--primary{ border-color:rgba(96,165,250,.45); background:rgba(96,165,250,.12); }
      .vsp-chip--accent{ border-color:rgba(34,211,238,.45); background:rgba(34,211,238,.10); }
      .vsp-chip--muted{ border-color:rgba(255,255,255,.14); background:rgba(255,255,255,.035); }
      .vsp-chip--ghost{ border-color:rgba(255,255,255,.10); background:transparent; }

      /* Collapsible raw JSON */
      .vsp-details{
        background:var(--vsp-card);
        border:1px solid var(--vsp-border);
        border-radius:14px;
        padding:10px 12px;
        margin:10px 0;
      }
      .vsp-details > summary{
        cursor:pointer;
        color:var(--vsp-text2);
        font-size:12px;
        list-style:none;
      }
      .vsp-pre{
        max-height:420px;
        overflow:auto;
        margin-top:10px;
        padding:10px;
        border-radius:12px;
        border:1px solid rgba(255,255,255,.08);
        background:rgba(0,0,0,.22);
      }
    `);

    hideLegacyTables();
    polishTables();
    decorateActionChips();
    collapseHugePre();

    // Re-run after async renders (Runs/DataSource sometimes render later)
    setTimeout(function(){
      hideLegacyTables();
      polishTables();
      decorateActionChips();
      collapseHugePre();
    }, 350);
  });
})();
"""
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended P123 polish into", p)
PY

echo "[OK] P123 applied."
echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
