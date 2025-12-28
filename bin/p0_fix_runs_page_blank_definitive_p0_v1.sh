#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need mkdir; need cp; need cat

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

# (1) New minimal JS (independent, no wrappers)
JS="static/js/vsp_runs_page_min_p0_v1.js"
mkdir -p static/js
[ -f "$JS" ] && cp -f "$JS" "${JS}.bak_${TS}" && echo "[BACKUP] ${JS}.bak_${TS}"

cat > "$JS" <<'JS'
/* VSP_RUNS_PAGE_MIN_P0_V1 */
(function(){
  const qs = (s, r=document)=>r.querySelector(s);
  const esc = (s)=>String(s??"").replace(/[&<>"]/g, c=>({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;" }[c]));
  async function fetchJSON(url, timeoutMs=6000){
    const ac = new AbortController();
    const t = setTimeout(()=>ac.abort(), timeoutMs);
    try{
      const r = await fetch(url, { cache:"no-store", signal: ac.signal, headers:{ "Accept":"application/json" } });
      const txt = await r.text();
      let j; try{ j = JSON.parse(txt); } catch(e){ throw new Error("bad json: " + txt.slice(0,140)); }
      return { httpOk: r.ok, status: r.status, json: j };
    } finally { clearTimeout(t); }
  }

  function render(items){
    const tbody = qs("#runs_tbody");
    const q = qs("#runs_q");
    const badge = qs("#runs_badge");
    if(!tbody) return;

    function apply(){
      const needle = (q?.value||"").trim().toLowerCase();
      tbody.innerHTML = "";
      let shown = 0;
      for(const it of items){
        const rid = it.run_id || "";
        if(needle && !rid.toLowerCase().includes(needle)) continue;
        shown++;
        const has = it.has || {};
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td class="rid">${esc(rid)}</td>
          <td>${has.summary ? "OK" : "-"}</td>
          <td>${has.json ? "OK" : "-"}</td>
          <td>${has.csv ? "OK" : "-"}</td>
          <td class="act">
            <a class="btn" href="/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=reports/run_gate_summary.json" target="_blank">SUMMARY</a>
            <a class="btn" href="/api/vsp/run_file?rid=${encodeURIComponent(rid)}&name=reports/findings_unified.json" target="_blank">JSON</a>
            <a class="btn" href="/api/vsp/export_csv?rid=${encodeURIComponent(rid)}" target="_blank">CSV</a>
          </td>`;
        tbody.appendChild(tr);
      }
      if(badge) badge.textContent = `runs: ${shown}/${items.length}`;
    }

    q && q.addEventListener("input", apply);
    apply();
  }

  async function main(){
    const st = qs("#runs_status");
    const badge = qs("#runs_badge");
    if(badge) badge.textContent = "runs: loading...";
    try{
      const r = await fetchJSON("/api/vsp/runs?limit=200", 8000);
      if(!r.httpOk) throw new Error("HTTP " + r.status);
      const j = r.json;
      if(!j || j.ok !== true || !Array.isArray(j.items)) throw new Error("bad contract: json.ok/items");
      if(st) st.textContent = `OK /api/vsp/runs (limit=${j.limit||200})`;
      render(j.items);
    }catch(e){
      console.error("[VSP][RUNS_MIN] failed:", e);
      if(st) st.textContent = "ERROR: " + (e?.message || String(e));
      if(badge) badge.textContent = "runs: error";
      const tbody = qs("#runs_tbody");
      if(tbody) tbody.innerHTML = `<tr><td colspan="5" class="muted">Runs API error: ${esc(e?.message||String(e))}</td></tr>`;
    }
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", main);
  else main();
})();
JS
echo "[OK] wrote $JS"

# (2) Overwrite /runs template => guaranteed visible (no older injected wrappers)
TPL="templates/vsp_runs_reports_v1.html"
[ -f "$TPL" ] && cp -f "$TPL" "${TPL}.bak_blankfix_${TS}" && echo "[BACKUP] ${TPL}.bak_blankfix_${TS}"

cat > "$TPL" <<'HTML'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>VSP Runs & Reports</title>
<style>
  body{margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;background:#0b1020;color:#e6e8ef;}
  .top{padding:14px 18px;border-bottom:1px solid rgba(255,255,255,.08);background:linear-gradient(180deg,rgba(255,255,255,.03),transparent);}
  .top h1{margin:0;font-size:18px;font-weight:650;}
  .row{display:flex;gap:10px;align-items:center;margin-top:10px;flex-wrap:wrap;}
  .badge{padding:6px 10px;border:1px solid rgba(255,255,255,.12);border-radius:999px;background:rgba(255,255,255,.04);font-size:12px;opacity:.95;}
  input{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.12);border-radius:10px;color:#e6e8ef;padding:10px 12px;min-width:260px;outline:none;}
  .wrap{padding:18px;}
  table{width:100%;border-collapse:collapse;border:1px solid rgba(255,255,255,.10);border-radius:14px;overflow:hidden;background:rgba(255,255,255,.03);}
  th,td{padding:10px 12px;border-bottom:1px solid rgba(255,255,255,.08);font-size:13px;}
  th{font-size:12px;letter-spacing:.04em;text-transform:uppercase;opacity:.85;background:rgba(255,255,255,.03);}
  tr:hover td{background:rgba(255,255,255,.03);}
  td.rid{font-family:ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono","Courier New", monospace;}
  .btn{display:inline-block;padding:6px 10px;border:1px solid rgba(255,255,255,.14);border-radius:10px;background:rgba(255,255,255,.04);color:#e6e8ef;text-decoration:none;font-size:12px;}
  .act{white-space:nowrap}
  .muted{opacity:.75}
</style>
</head>
<body>
  <div class="top">
    <h1>VSP Runs & Reports</h1>
    <div class="row">
      <span id="runs_status" class="badge muted">boot...</span>
      <span id="runs_badge" class="badge">runs: -</span>
      <input id="runs_q" placeholder="Filter by run_id..." autocomplete="off">
      <a class="btn" href="/vsp5">Back to /vsp5</a>
      <a class="btn" href="/api/vsp/runs?limit=200" target="_blank">Open runs JSON</a>
    </div>
  </div>

  <div class="wrap">
    <table>
      <thead>
        <tr>
          <th style="width:55%">run_id</th>
          <th>summary</th>
          <th>json</th>
          <th>csv</th>
          <th style="width:1%">quick open</th>
        </tr>
      </thead>
      <tbody id="runs_tbody">
        <tr><td colspan="5" class="muted">Loading…</td></tr>
      </tbody>
    </table>
  </div>

  <script src="/static/js/vsp_runs_page_min_p0_v1.js?v={{ asset_v }}"></script>
</body>
</html>
HTML
echo "[OK] wrote $TPL"

# (3) Restart UI
bin/p1_ui_8910_single_owner_start_v2.sh || true

echo
echo "[NEXT] Open Incognito once:"
echo "  http://127.0.0.1:8910/runs"
echo "If vẫn trắng: DevTools > Application > Clear site data, rồi F5."
