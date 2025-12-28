#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

MARK="VSP_P0_DASH_ONLY_TOPFIND_REBIND_V3"
if grep -q "$MARK" "$JS"; then
  echo "[SKIP] already patched: $MARK"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_rebind_v3_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_rebind_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

block = textwrap.dedent(r"""
/* VSP_P0_DASH_ONLY_TOPFIND_REBIND_V3
   - Hard rebind "Load top findings" button (clone node => drop all old listeners)
   - Fetch only CSV: reports/findings_unified.csv (allowlisted 200)
   - Render into existing "Top findings" table (or create if missing)
*/
(()=> {
  if (window.__vsp_p0_dash_only_topfind_rebind_v3) return;
  window.__vsp_p0_dash_only_topfind_rebind_v3 = true;

  const BASE = window.location.origin;
  const API_RID = `${BASE}/api/vsp/rid_latest_gate_root`;
  const API_RUNFILE = (rid, path)=> `${BASE}/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
  const CSV_PATH = "reports/findings_unified.csv";

  const norm = (v)=> (v==null ? "" : String(v)).trim();
  const SEV_W = {CRITICAL: 600, HIGH: 500, MEDIUM: 400, LOW: 300, INFO: 200, TRACE: 100};
  const sevNorm = (v)=>{
    const x = norm(v).toUpperCase();
    if (!x) return "";
    if (x === "CRIT") return "CRITICAL";
    return x;
  };

  const log = (...a)=> console.log("[VSP][DASH_ONLY][TOPFIND_V3]", ...a);

  async function fetchJson(url){
    const r = await fetch(url, {credentials:"same-origin"});
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.json();
  }
  async function fetchText(url){
    const r = await fetch(url, {credentials:"same-origin"});
    if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`);
    return await r.text();
  }

  // small CSV parser w/ quotes
  function parseCsv(text){
    const rows = [];
    let row = [], field = "", i = 0, inQ = false;
    while (i < text.length){
      const c = text[i];
      if (inQ){
        if (c === '"'){
          if (text[i+1] === '"'){ field += '"'; i += 2; continue; }
          inQ = false; i++; continue;
        }
        field += c; i++; continue;
      } else {
        if (c === '"'){ inQ = true; i++; continue; }
        if (c === ','){ row.push(field); field = ""; i++; continue; }
        if (c === '\r'){ i++; continue; }
        if (c === '\n'){ row.push(field); rows.push(row); row = []; field = ""; i++; continue; }
        field += c; i++; continue;
      }
    }
    if (field.length || row.length){ row.push(field); rows.push(row); }
    return rows;
  }

  function findLoadButton(){
    const cands = Array.from(document.querySelectorAll("button, a, [role='button'], input[type='button'], input[type='submit']"));
    const hit = cands.find(el => /load\s+top\s+findings/i.test(norm(el.textContent || el.value || "")));
    return hit || null;
  }

  function findTopFindingsTable(){
    // Prefer: a table inside a container that mentions "Top findings"
    const tables = Array.from(document.querySelectorAll("table"));
    for (const t of tables){
      const box = t.closest("div, section, article") || t.parentElement;
      if (box && /top\s+findings/i.test(norm(box.textContent))) return t;
      // also accept if header looks like our table
      const ths = Array.from(t.querySelectorAll("th")).map(x=>norm(x.textContent).toLowerCase());
      if (ths.includes("severity") && ths.includes("tool")) return t;
    }
    // Else create inside the "Top findings" card/container
    const blocks = Array.from(document.querySelectorAll("div, section, article"));
    const host = blocks.find(el => /top\s+findings/i.test(norm(el.textContent)));
    if (!host) return null;

    const table = document.createElement("table");
    table.style.width = "100%";
    table.style.borderCollapse = "collapse";
    table.innerHTML = `
      <thead>
        <tr>
          <th style="text-align:left;padding:8px;">Severity</th>
          <th style="text-align:left;padding:8px;">Tool</th>
          <th style="text-align:left;padding:8px;">Title</th>
          <th style="text-align:left;padding:8px;">Location</th>
        </tr>
      </thead>
      <tbody>
        <tr><td colspan="4" style="padding:8px;opacity:.75;">Not loaded</td></tr>
      </tbody>`;
    host.appendChild(table);
    return table;
  }

  function renderRows(table, rows){
    const tbody = table.querySelector("tbody") || table.appendChild(document.createElement("tbody"));
    tbody.innerHTML = "";
    for (const r of rows){
      const tr = document.createElement("tr");
      const loc = r.file ? (r.line ? `${r.file}:${r.line}` : r.file) : "";
      const title = r.title || r.rule_id || "";
      const sev = r.severity || "";
      tr.innerHTML = `
        <td style="padding:8px;white-space:nowrap;">${escapeHtml(sev)}</td>
        <td style="padding:8px;white-space:nowrap;">${escapeHtml(r.tool||"")}</td>
        <td style="padding:8px;">${escapeHtml(title)}</td>
        <td style="padding:8px;white-space:nowrap;">${escapeHtml(loc)}</td>
      `;
      tbody.appendChild(tr);
    }
    if (!rows.length){
      const tr = document.createElement("tr");
      tr.innerHTML = `<td colspan="4" style="padding:8px;opacity:.75;">No findings</td>`;
      tbody.appendChild(tr);
    }
  }

  function escapeHtml(s){
    return norm(s)
      .replaceAll("&","&amp;")
      .replaceAll("<","&lt;")
      .replaceAll(">","&gt;")
      .replaceAll('"',"&quot;")
      .replaceAll("'","&#39;");
  }

  async function loadTopFindingsCsv(limit){
    const ridj = await fetchJson(API_RID);
    const rid = ridj && ridj.rid;
    if (!rid) throw new Error("rid_latest_gate_root returned no rid");
    const csv = await fetchText(API_RUNFILE(rid, CSV_PATH));

    const rows = parseCsv(csv);
    if (!rows.length) return [];
    const hdr = rows[0].map(x=>norm(x).toLowerCase());
    const idx = (k)=> hdr.indexOf(k);

    const out = [];
    for (let i=1;i<rows.length;i++){
      const a = rows[i];
      if (!a || !a.length) continue;
      const sev = sevNorm(a[idx("severity")] ?? "");
      const tool = norm(a[idx("tool")] ?? "");
      const rule_id = norm(a[idx("rule_id")] ?? "");
      const title = norm(a[idx("title")] ?? "");
      const file = norm(a[idx("file")] ?? "");
      const line = norm(a[idx("line")] ?? "");
      const msg = norm(a[idx("message")] ?? "");
      out.push({severity:sev, tool, rule_id, title: title || msg || rule_id, file, line});
    }

    out.sort((x,y)=>{
      const wx = SEV_W[x.severity] || 0;
      const wy = SEV_W[y.severity] || 0;
      if (wy !== wx) return wy - wx;
      if (x.tool !== y.tool) return (x.tool < y.tool ? -1 : 1);
      return (x.title < y.title ? -1 : (x.title > y.title ? 1 : 0));
    });

    return out.slice(0, limit);
  }

  function rebind(){
    const btn = findLoadButton();
    if (!btn) return false;

    // CLONE NODE => wipe all old listeners from previous patches
    const clone = btn.cloneNode(true);
    btn.parentNode.replaceChild(clone, btn);

    clone.addEventListener("click", async (e)=>{
      try{
        e.preventDefault();
        e.stopPropagation();

        const table = findTopFindingsTable();
        if (!table) { alert("Top findings table not found."); return; }

        clone.disabled = true;
        clone.style.opacity = "0.8";
        clone.textContent = "Loading…";

        const rows = await loadTopFindingsCsv(25);
        renderRows(table, rows);

        clone.textContent = "Load top findings (25)";
        log("rendered rows=", rows.length);
      } catch(err){
        console.warn("[VSP][DASH_ONLY][TOPFIND_V3] load failed:", err);
        try{ alert("Load top findings failed: " + (err && err.message ? err.message : String(err))); } catch(_){}
        clone.textContent = "Load top findings (25)";
      } finally{
        clone.disabled = false;
        clone.style.opacity = "";
      }
    }, {capture:true});

    log("rebind OK (clone+listener attached)");
    return true;
  }

  // try a few times because DOM renders async
  let tries = 0;
  const t = setInterval(()=>{
    tries++;
    if (rebind() || tries >= 10) clearInterval(t);
  }, 600);

})();
""").strip() + "\n"

p.write_text(s + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", "VSP_P0_DASH_ONLY_TOPFIND_REBIND_V3")
PY

node --check "$JS"
echo "[OK] node --check passed"

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R) then click: Load top findings (25)."
