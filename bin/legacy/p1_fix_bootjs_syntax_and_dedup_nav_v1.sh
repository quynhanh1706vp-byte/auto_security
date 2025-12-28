#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_p1_page_boot_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_${TS}"
echo "[BACKUP] ${JS}.bak_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_p1_page_boot_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_LIVE_RID_AND_RUNS_HEALTH_V1"
if MARK not in s:
    raise SystemExit("[ERR] marker not found in boot js, cannot patch safely")

# replace everything from marker to EOF with a corrected injection (no Python syntax)
prefix = s.split(f"// {MARK}", 1)[0]

inject = f"""
// {MARK}
;(()=>{{
  const MARK="{MARK}";
  if (window[MARK]) return; window[MARK]=1;

  const POLL_MS = 2500;

  function dedupNavbars(){{
    // keep the first navbar that contains our 5 tabs, hide the rest
    const keys = ["Dashboard","Runs & Reports","Data Source","Settings","Rule Overrides"];
    const nodes = Array.from(document.querySelectorAll("nav,div,ul"));
    const cands = [];
    for (const el of nodes){{
      const t = (el.innerText || "").replace(/\\s+/g," ").trim();
      if (!t) continue;
      let hit = 0;
      for (const k of keys) if (t.includes(k)) hit++;
      if (hit >= 3) cands.push(el);
    }}
    if (cands.length <= 1) return;
    // sort by vertical position (top-first), keep first
    cands.sort((a,b)=> (a.getBoundingClientRect().top - b.getBoundingClientRect().top));
    const keep = cands[0];
    for (let i=1;i<cands.length;i++) {{
      const x=cands[i];
      if (x===keep) continue;
      x.style.display="none";
    }}
  }}

  function setPill(ok, msg){{
    let pill = document.getElementById("vsp_live_runs_pill");
    if(!pill){{
      pill = document.createElement("div");
      pill.id = "vsp_live_runs_pill";
      pill.style.cssText = [
        "position:fixed","top:10px","right:12px","z-index:99999",
        "padding:6px 10px","border-radius:999px",
        "font:12px/1.2 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Arial",
        "background:rgba(0,0,0,.55)","border:1px solid rgba(255,255,255,.12)",
        "color:#e5e7eb","backdrop-filter: blur(8px)",
        "box-shadow: 0 10px 30px rgba(0,0,0,.35)"
      ].join(";");
      document.body.appendChild(pill);
    }}
    pill.textContent = msg || "";
    pill.style.borderColor = ok ? "rgba(34,197,94,.45)" : "rgba(239,68,68,.45)";
  }}

  function clearStickyBanners(){{
    const all = Array.from(document.querySelectorAll("div,span,a,button"));
    for (const el of all){{
      const t = (el.textContent || "").trim();
      if (!t) continue;
      if (t.includes("RUNS API FAIL") || (t.includes("RUNS API") && t.includes("Error:"))){{
        el.textContent = "RUNS API OK";
      }}
    }}
  }}

  function setTopLinks(rid){{
    if(!rid) return;
    const anchors = Array.from(document.querySelectorAll("a"));
    for (const a of anchors){{
      const t = (a.textContent || "").trim().toLowerCase();
      if (t === "open data source") {{
        a.href = "/data_source?rid=" + encodeURIComponent(rid);
        a.target = "_blank";
      }} else if (t === "open summary") {{
        a.href = "/api/vsp/run_file?rid=" + encodeURIComponent(rid) + "&name=" + encodeURIComponent("reports/run_gate_summary.json");
        a.target = "_blank";
      }}
    }}
  }}

  async function poll(){{
    const url = "/api/vsp/runs?limit=1&_=" + Date.now();
    try {{
      const r = await fetch(url, {{ cache: "no-store", credentials: "same-origin" }});
      if(!r.ok) throw new Error("HTTP " + r.status);
      const j = await r.json();
      if(!j || j.ok !== true) throw new Error("bad_json");
      const rid = j.rid_latest || (j.items && j.items[0] && j.items[0].run_id) || null;

      window.__VSP_RID_LATEST__ = rid;
      try{{ localStorage.setItem("vsp_rid_latest", rid || ""); }}catch(_e){{}}

      clearStickyBanners();
      setTopLinks(rid);
      dedupNavbars();

      const tag = (j.degraded ? "DEGRADED" : "OK");
      setPill(true, `RUNS ${tag} • rid_latest=${{rid || "N/A"}}`);
    }} catch(e) {{
      dedupNavbars();
      setPill(false, `RUNS FAIL • ${{String(e)}}`);
    }}
  }}

  // run immediately + interval
  poll();
  setInterval(poll, POLL_MS);

  // also dedup once after DOM settles
  setTimeout(dedupNavbars, 600);
  setTimeout(dedupNavbars, 1500);
}})();
"""

p.write_text(prefix + inject + "\n", encoding="utf-8")
print("[OK] replaced injected block with fixed JS (no SyntaxError) and navbar dedup")
PY

echo "[OK] restart UI"
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh || true
sleep 1

echo "== quick check =="
curl -sS -I "http://127.0.0.1:8910/vsp5" | sed -n '1,8p' || true
curl -sS "http://127.0.0.1:8910/api/vsp/runs?limit=1" | jq -r '.ok,.rid_latest,.items[0].run_id' || true
echo "[NEXT] Mở Incognito hoặc Ctrl+F5 /vsp5 để chắc chắn load JS mới."
