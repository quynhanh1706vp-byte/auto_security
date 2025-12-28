#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_runs_reports_v1.html"
JS="static/js/vsp_runs_kpi_compact_v3.js"

[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
[ -f "$JS" ]  || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_autofill_${TS}"
echo "[BACKUP] ${JS}.bak_autofill_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time, textwrap

tpl = Path("templates/vsp_runs_reports_v1.html").read_text(encoding="utf-8", errors="replace")
js_path = Path("static/js/vsp_runs_kpi_compact_v3.js")
js = js_path.read_text(encoding="utf-8", errors="replace")

# collect all ids vsp_runs_kpi_* from template
ids = sorted(set(re.findall(r'id="(vsp_runs_kpi_[a-zA-Z0-9_]+)"', tpl)))
if not ids:
    raise SystemExit("[ERR] no vsp_runs_kpi_* ids found in template")

marker = "VSP_P2_RUNS_KPI_AUTOFILL_FROM_TEMPLATE_V1"
if marker in js:
    print("[OK] marker already present, skip append")
    raise SystemExit(0)

# simple mapping by suffix
def key_for_id(i: str) -> str:
    # commonly: vsp_runs_kpi_total_runs_window => total_runs
    s = re.sub(r"^vsp_runs_kpi_", "", i)
    s = re.sub(r"_window$", "", s)
    return s.lower()

id_keys = [(i, key_for_id(i)) for i in ids]

payload = {
  "ids": id_keys
}

block = textwrap.dedent(f"""
/* ===================== {marker} ===================== */
(()=>{{
  function setText(id, v){{
    const el = document.getElementById(id);
    if (!el) return false;
    el.textContent = (v===null || v===undefined) ? "—" : String(v);
    return true;
  }}

  async function fetchKpi(days){{
    const q = encodeURIComponent(String(days||30));
    const urls = [`/api/ui/runs_kpi_v2?days=${{q}}`, `/api/ui/runs_kpi_v1?days=${{q}}`];
    let last = null;
    for (const u of urls){{
      try{{
        const r = await fetch(u, {{cache:"no-store"}});
        const j = await r.json();
        if (j && j.ok) return j;
        last = new Error(j?.err || "not ok");
      }}catch(e){{ last = e; }}
    }}
    throw last || new Error("kpi fetch failed");
  }}

  function fillFromData(d){{
    // template-driven fill (no layout changes)
    const pairs = {payload["ids"]!r};
    for (const [id, key] of pairs){{
      let v = null;

      if (key === "total_runs") v = d.total_runs;
      else if (key === "latest_rid") v = d.latest_rid;
      else if (key === "has_findings") v = d.has_findings;
      else if (key === "has_gate") v = d.has_gate;
      else if (key in (d.by_overall||{{}})) v = d.by_overall[key];
      else if (key.upper() in (d.by_overall||{{}})) v = d.by_overall[key.upper()];
      else if (key === "green") v = d.by_overall?.GREEN;
      else if (key === "amber") v = d.by_overall?.AMBER;
      else if (key === "red") v = d.by_overall?.RED;
      else if (key === "unknown") v = d.by_overall?.UNKNOWN;
      else if (key === "ts") v = d.ts;

      setText(id, v);
    }}
  }}

  async function boot(){{
    try{{
      const sel = document.getElementById("vsp_runs_kpi_window_sel");
      const days = sel ? Number(sel.value||30) : 30;
      const d = await fetchKpi(days);
      fillFromData(d);
    }}catch(e){{
      // silent safe (no crash)
      // If you want debug: console.warn("[KPI_AUTOFILL] failed", e);
    }}
  }}

  if (document.readyState === "loading") {{
    document.addEventListener("DOMContentLoaded", ()=> setTimeout(boot, 0));
  }} else {{
    setTimeout(boot, 0);
  }}

  // hook Reload KPI button if exists
  const btn = document.getElementById("vsp_runs_kpi_reload_btn");
  if (btn) btn.addEventListener("click", (ev)=>{{ ev.preventDefault(); boot(); }});
}})();
/* ===================== /{marker} ===================== */
""").strip()+"\n"

js_path.write_text(js + "\n\n" + block, encoding="utf-8")
print("[OK] appended", marker, "ids=", len(ids))
PY

node --check "$JS" >/dev/null
echo "[OK] node --check OK"
echo "[DONE] p2_runs_kpi_compact_autofill_from_template_v1 (restart service)"
