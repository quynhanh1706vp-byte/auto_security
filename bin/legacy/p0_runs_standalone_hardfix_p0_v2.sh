#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ss; need awk; need sed; need curl; need python3
command -v node >/dev/null 2>&1 || echo "[WARN] node not found (skip JS syntax checks)"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "${TPL}.bak_standalone_hardfix_${TS}"
echo "[BACKUP] ${TPL}.bak_standalone_hardfix_${TS}"

cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>VSP Runs & Reports</title>
  <!-- VSP_RUNS_STANDALONE_HARDFIX_P0_V2 -->
  <style>
    :root{
      --bg:#070A12; --panel:#0B1020; --panel2:#0E1630; --txt:#D7DEF7;
      --muted:#92A0C9; --line:#1B2A55; --ok:#3EE07A; --bad:#FF5C6A;
      --warn:#FFB020; --chip:#0F1B3D;
    }
    *{box-sizing:border-box}
    body{margin:0;background:radial-gradient(1000px 700px at 20% 10%, #10183a 0%, var(--bg) 60%); color:var(--txt);
         font:14px/1.35 system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,"Helvetica Neue",Arial}
    a{color:inherit;text-decoration:none}
    .wrap{max-width:1200px;margin:20px auto;padding:0 16px}
    .topbar{display:flex;gap:10px;align-items:center;justify-content:space-between;margin-bottom:12px}
    .brand{display:flex;gap:10px;align-items:center}
    .badge{padding:4px 10px;border:1px solid var(--line);border-radius:999px;background:rgba(20,30,60,.35);color:var(--muted)}
    .btn{padding:8px 12px;border:1px solid var(--line);border-radius:10px;background:rgba(10,16,32,.6);cursor:pointer}
    .btn:hover{filter:brightness(1.08)}
    .panel{background:rgba(8,12,24,.55);border:1px solid var(--line);border-radius:14px;padding:12px}
    .row{display:flex;flex-wrap:wrap;gap:10px;align-items:center;justify-content:space-between;margin:10px 0}
    input{padding:9px 10px;border:1px solid var(--line);border-radius:10px;background:rgba(10,16,32,.6);color:var(--txt);min-width:260px}
    .mini{color:var(--muted);font-size:12px}
    table{width:100%;border-collapse:separate;border-spacing:0;margin-top:10px;overflow:hidden;border-radius:12px}
    thead th{position:sticky;top:0;background:rgba(14,22,48,.9);backdrop-filter:blur(6px);
             color:var(--muted);font-weight:600;text-align:left;padding:10px;border-bottom:1px solid var(--line)}
    tbody td{padding:10px;border-bottom:1px solid rgba(27,42,85,.45);vertical-align:middle}
    tbody tr:hover{background:rgba(15,27,61,.25)}
    .pill{display:inline-block;padding:3px 8px;border-radius:999px;background:var(--chip);border:1px solid rgba(27,42,85,.65);margin-right:6px}
    .yes{color:var(--ok)} .no{color:var(--bad)}
    .actions{display:flex;gap:8px;flex-wrap:wrap}
    .act{padding:6px 10px;border-radius:10px;border:1px solid rgba(27,42,85,.75);background:rgba(10,16,32,.55)}
    .act:hover{filter:brightness(1.1)}
    .err{margin-top:10px;color:#FFD0D6}
  </style>

  <script>
  // Kill sticky banners/flags that made /runs go white before
  (function(){
    try{
      const keys = Object.keys(localStorage||{});
      const bad = keys.filter(k => /runs|vsp|degrad|fail|banner|api/i.test(k));
      bad.forEach(k=>{ try{ localStorage.removeItem(k); }catch(_){ } });
      try{ sessionStorage && Object.keys(sessionStorage).forEach(k=>{ if(/runs|vsp|fail/i.test(k)) sessionStorage.removeItem(k); }); }catch(_){}
    }catch(_){}
  })();
  </script>
</head>

<body>
  <div class="wrap">
    <div class="topbar">
      <div class="brand">
        <div style="font-weight:800;letter-spacing:.2px">VSP Runs & Reports</div>
        <span class="badge" id="apiState">api: …</span>
        <span class="badge" id="ridLatest">rid_latest: …</span>
        <span class="badge" id="count">items: …</span>
      </div>
      <div style="display:flex;gap:8px;align-items:center">
        <button class="btn" id="reloadBtn">Refresh</button>
        <a class="btn" href="/vsp5">Go /vsp5</a>
      </div>
    </div>

    <div class="panel">
      <div class="row">
        <div>
          <div class="mini">Source: <span id="rootsUsed">/home/test/Data/SECURITY_BUNDLE/out</span></div>
          <div class="mini">Fetch: <code>/api/vsp/runs?limit=200</code></div>
        </div>
        <div style="display:flex;gap:10px;align-items:center">
          <input id="q" placeholder="Filter by run_id..." />
          <span class="mini" id="shown"></span>
        </div>
      </div>

      <div class="err" id="err" style="display:none"></div>

      <table>
        <thead>
          <tr>
            <th style="width:38%">RID</th>
            <th>JSON</th>
            <th>CSV</th>
            <th>SARIF</th>
            <th>SUMMARY</th>
            <th style="width:28%">Actions</th>
          </tr>
        </thead>
        <tbody id="tb"></tbody>
      </table>
    </div>
  </div>

<script>
(function(){
  const tb = document.getElementById('tb');
  const q  = document.getElementById('q');
  const err = document.getElementById('err');
  const apiState = document.getElementById('apiState');
  const ridLatest = document.getElementById('ridLatest');
  const rootsUsed = document.getElementById('rootsUsed');
  const count = document.getElementById('count');
  const shown = document.getElementById('shown');

  const esc = (s)=>String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  const pill = (ok)=>`<span class="pill ${ok?'yes':'no'}">${ok?'true':'false'}</span>`;

  function linkAct(label, href){
    return `<a class="act" href="${href}" target="_blank" rel="noopener">${label}</a>`;
  }

  function render(items){
    const f = (q.value||"").trim().toLowerCase();
    const xs = f ? items.filter(it => (it.run_id||"").toLowerCase().includes(f)) : items;
    shown.textContent = `showing ${xs.length} / ${items.length}`;
    tb.innerHTML = xs.map(it=>{
      const rid = it.run_id || "";
      const has = it.has || {};
      const summaryHref = `/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`;
      const tgzHref = `/api/vsp/export_tgz?rid=${encodeURIComponent(rid)}&scope=reports`;
      const csvHref = `/api/vsp/export_csv?rid=${encodeURIComponent(rid)}`;
      const shaHref = `/api/vsp/sha256?rid=${encodeURIComponent(rid)}&name=${encodeURIComponent("reports/run_gate_summary.json")}`;

      return `<tr>
        <td><code>${esc(rid)}</code></td>
        <td>${pill(!!has.json)}</td>
        <td>${pill(!!has.csv)}</td>
        <td>${pill(!!has.sarif)}</td>
        <td>${pill(!!has.summary)}</td>
        <td class="actions">
          ${linkAct("summary", summaryHref)}
          ${linkAct("csv", csvHref)}
          ${linkAct("tgz", tgzHref)}
          ${linkAct("sha", shaHref)}
        </td>
      </tr>`;
    }).join("");
  }

  async function load(){
    err.style.display="none";
    apiState.textContent = "api: loading…";
    try{
      const r = await fetch(`/api/vsp/runs?limit=200`, {cache:"no-store"});
      const j = await r.json().catch(()=>null);
      if(!r.ok || !j || j.ok !== true || !Array.isArray(j.items)){
        throw new Error(`bad response: http=${r.status} json_ok=${j&&j.ok}`);
      }
      apiState.textContent = `api: OK (${j.items.length})`;
      ridLatest.textContent = `rid_latest: ${(j.rid_latest||"N/A")}`;
      rootsUsed.textContent = (j.roots_used && j.roots_used[0]) ? j.roots_used.join(", ") : rootsUsed.textContent;
      count.textContent = `items: ${j.items.length}`;
      window.__VSP_RUNS_ITEMS = j.items;
      render(j.items);
    }catch(e){
      apiState.textContent = "api: FAIL";
      err.textContent = String(e && e.message ? e.message : e);
      err.style.display="block";
      tb.innerHTML = "";
    }
  }

  document.getElementById('reloadBtn').addEventListener('click', load);
  q.addEventListener('input', ()=>{ if(window.__VSP_RUNS_ITEMS) render(window.__VSP_RUNS_ITEMS); });

  load();
})();
</script>

</body>
</html>
HTML

# restart clean
rm -f /tmp/vsp_ui_8910.lock /tmp/vsp_ui_8910.lock.* 2>/dev/null || true
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/{print $NF}' | sed -n 's/.*pid=\\([0-9]\\+\\).*/\\1/p' | sort -u | tr '\n' ' ')"
[ -n "${PIDS// }" ] && kill -9 $PIDS || true

# start (use your standard script if exists)
if [ -x bin/p1_ui_8910_single_owner_start_v2.sh ]; then
  bin/p1_ui_8910_single_owner_start_v2.sh || true
fi

echo "== verify =="
curl -sS -I http://127.0.0.1:8910/runs | head -n 8 || true
curl -sS http://127.0.0.1:8910/runs | grep -n "VSP_RUNS_STANDALONE_HARDFIX_P0_V2" || true
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=1" | head -n 8 || true
echo "[DONE] Open INCOGNITO: http://127.0.0.1:8910/runs"
