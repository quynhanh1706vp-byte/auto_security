#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need curl

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import time

ts = time.strftime("%Y%m%d_%H%M%S")

tpl = Path("templates/vsp_runs_reports_v1.html")
js  = Path("static/js/vsp_runs_page_min_p0_v2.js")
tpl.parent.mkdir(parents=True, exist_ok=True)
js.parent.mkdir(parents=True, exist_ok=True)

if tpl.exists():
    tpl_bak = tpl.with_name(tpl.name + f".bak_hardreset_{ts}")
    tpl_bak.write_text(tpl.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[BACKUP]", tpl_bak)

if js.exists():
    js_bak = js.with_name(js.name + f".bak_hardreset_{ts}")
    js_bak.write_text(js.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
    print("[BACKUP]", js_bak)

JS = r"""/* VSP_RUNS_PAGE_MIN_P0_V2 */
(function(){
  const $ = (sel, r=document)=>r.querySelector(sel);
  const esc = (s)=>String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  const API="/api/vsp/runs";

  let LAST=null;

  function setBanner(kind, msg){
    const b=$("#banner");
    if(!b) return;
    b.className = "banner " + (kind||"");
    b.textContent = msg || "";
    b.style.display = msg ? "block" : "none";
  }

  function render(items){
    const tbody=$("#runs_tbody");
    const loaded=$("#runs_loaded");
    if(loaded) loaded.textContent = String(items.length);
    if(!tbody) return;
    tbody.innerHTML="";
    for(const it of items){
      const rid = String(it?.run_id ?? "");
      const has = it?.has || {};
      const tr = document.createElement("tr");

      const tdRid = document.createElement("td");
      tdRid.innerHTML = `<code class="rid">${esc(rid)}</code>`;
      tr.appendChild(tdRid);

      const tdHas = document.createElement("td");
      const mk = (k)=> (has && has[k]) ? `<span class="ok">${k}:OK</span>` : `<span class="no">${k}:-</span>`;
      tdHas.innerHTML = `<div class="has">${mk("json")} ${mk("csv")} ${mk("sarif")} ${mk("summary")}</div>`;
      tr.appendChild(tdHas);

      const tdAct = document.createElement("td");
      const uSummary = `/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`;
      const uCsv     = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
      const uTgz     = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
      const uSha     = `/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`;
      tdAct.innerHTML = `
        <a class="btn" target="_blank" rel="noopener" href="${uSummary}">SUMMARY</a>
        <a class="btn" target="_blank" rel="noopener" href="${uCsv}">CSV</a>
        <a class="btn" target="_blank" rel="noopener" href="${uTgz}">TGZ</a>
        <a class="btn" target="_blank" rel="noopener" href="${uSha}">SHA</a>
      `;
      tr.appendChild(tdAct);

      tbody.appendChild(tr);
    }
  }

  function applyFilter(){
    if(!LAST){ return; }
    const q = ($("#q")?.value || "").trim().toLowerCase();
    let items = Array.isArray(LAST.items) ? LAST.items : [];
    if(q) items = items.filter(it=>String(it?.run_id||"").toLowerCase().includes(q));
    render(items);
    setBanner("", "");
  }

  async function reload(){
    setBanner("warn", "Loading runs…");
    const limit = parseInt(($("#limit")?.value || "200"), 10) || 200;
    const url = `${API}?limit=${encodeURIComponent(String(limit))}&_ts=${Date.now()}`;
    try{
      const resp = await fetch(url, {cache:"no-store", credentials:"same-origin"});
      const txt = await resp.text();
      let data;
      try{ data = JSON.parse(txt); } catch(e){ throw new Error("Bad JSON: " + txt.slice(0,160)); }
      if(!data || data.ok !== true || !Array.isArray(data.items)){
        throw new Error("Bad contract (expect {ok:true, items:[]})");
      }
      LAST = data;
      applyFilter();
      setBanner("", "");
    }catch(e){
      console.error("[RUNS_MIN] load failed:", e);
      setBanner("err", "RUNS API FAIL: " + (e?.message || String(e)));
    }
  }

  document.addEventListener("DOMContentLoaded", ()=>{
    $("#reload")?.addEventListener("click", ()=>reload());
    $("#q")?.addEventListener("input", ()=>applyFilter());
    $("#limit")?.addEventListener("change", ()=>reload());

    // show something immediately (never blank)
    setBanner("warn", "Booting /runs…");
    reload();
  });
})();
"""

HTML = r"""<!-- VSP_RUNS_MIN_PAGE_P0_V2 -->
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>VSP Runs & Reports</title>
  <style>
    :root{ color-scheme: dark; }
    body{ margin:0; font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial;
          background:#070b14; color:#d6e2ff; }
    .wrap{ max-width:1200px; margin:0 auto; padding:18px 16px 40px; }
    h1{ font-size:18px; margin:0 0 10px; letter-spacing:.2px; }
    .bar{ display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin:10px 0 12px; }
    input, select{ background:#0b1222; border:1px solid rgba(255,255,255,.10); color:#d6e2ff;
                   padding:8px 10px; border-radius:10px; outline:none; }
    .btn2{ background:#0b1222; border:1px solid rgba(255,255,255,.10); color:#d6e2ff; padding:8px 10px;
           border-radius:10px; cursor:pointer; }
    .meta{ opacity:.75; font-size:12px; }
    .banner{ display:none; margin:10px 0; padding:10px 12px; border-radius:12px; font-size:13px; }
    .banner.warn{ background:rgba(255,200,0,.10); border:1px solid rgba(255,200,0,.35); }
    .banner.err{ background:rgba(255,70,70,.10); border:1px solid rgba(255,70,70,.35); }
    table{ width:100%; border-collapse:collapse; overflow:hidden; border-radius:14px;
           border:1px solid rgba(255,255,255,.08); }
    thead th{ text-align:left; font-size:12px; opacity:.75; padding:10px 12px; background:#0a1020; }
    tbody td{ padding:10px 12px; border-top:1px solid rgba(255,255,255,.06); vertical-align:top; }
    code.rid{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New";
              font-size:12px; }
    .has{ display:flex; gap:10px; flex-wrap:wrap; font-family: ui-monospace, monospace; font-size:12px; }
    .ok{ color:#7CFFB6; }
    .no{ color:#ff7a7a; }
    a.btn{ display:inline-block; padding:6px 10px; border-radius:10px; margin-right:6px;
           border:1px solid rgba(255,255,255,.10); background:#0b1222; color:#d6e2ff; text-decoration:none; }
    a.btn:hover, .btn2:hover{ filter:brightness(1.08); }
  </style>
</head>
<body>
  <div class="wrap">
    <h1>VSP Runs & Reports</h1>
    <div class="meta">Marker: <b>VSP_RUNS_MIN_PAGE_P0_V2</b> · Runs loaded: <b id="runs_loaded">0</b></div>

    <div class="bar">
      <button class="btn2" id="reload">Reload</button>
      <label class="meta">limit:
        <select id="limit">
          <option>20</option>
          <option>50</option>
          <option selected>200</option>
          <option>500</option>
        </select>
      </label>
      <input id="q" placeholder="Filter by run_id..." size="28"/>
      <span class="meta">API: <code>/api/vsp/runs</code></span>
    </div>

    <div id="banner" class="banner warn"></div>

    <table>
      <thead>
        <tr>
          <th style="width:55%">Run</th>
          <th style="width:25%">Artifacts</th>
          <th style="width:20%">Quick open</th>
        </tr>
      </thead>
      <tbody id="runs_tbody">
        <tr><td colspan="3" class="meta">Booting…</td></tr>
      </tbody>
    </table>
  </div>

  <script src="/static/js/vsp_runs_page_min_p0_v2.js?v=__V__"></script>
</body>
</html>
"""

# replace cache buster
HTML = HTML.replace("__V__", ts)

js.write_text(JS, encoding="utf-8")
tpl.write_text(HTML, encoding="utf-8")
print("[OK] wrote", js)
print("[OK] wrote", tpl)
PY

echo "== restart clean (kill lock + kill :8910) =="
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true

bin/p1_ui_8910_single_owner_start_v2.sh || true

echo "== quick verify =="
curl -sS http://127.0.0.1:8910/runs | head -n 5
echo
grep -n "VSP_RUNS_MIN_PAGE_P0_V2" -n templates/vsp_runs_reports_v1.html | head -n 3 || true
