#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JSF="static/js/vsp_ui_4tabs_commercial_v1.js"
TPL="templates/vsp_4tabs_commercial_v1.html"

[ -f "$JSF" ] || { echo "[ERR] missing $JSF (need /vsp4 patch first)"; exit 1; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL (need /vsp4 patch first)"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JSF"  "$JSF.bak_export_ds_${TS}"
cp -f "$TPL"  "$TPL.bak_export_ds_${TS}"
echo "[BACKUP] $JSF.bak_export_ds_${TS}"
echo "[BACKUP] $TPL.bak_export_ds_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

# ---------- Patch template: add Export panel + DataSource blocks ----------
tpl = Path("templates/vsp_4tabs_commercial_v1.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

TAG = "<!-- === VSP4_EXPORT_DS_V1 === -->"
if TAG not in t:
    # Insert export panel into Runs tab (top)
    runs_anchor = '  <section id="tab-runs" style="display:none">'
    if runs_anchor in t:
        insert = runs_anchor + "\n" + TAG + r'''
        <div class="vsp-card" style="margin-bottom:14px">
          <div class="vsp-row" style="justify-content:space-between;align-items:flex-start">
            <div>
              <div style="font-weight:800">Export (selected run)</div>
              <div class="vsp-muted" style="font-size:12px;line-height:1.6;margin-top:4px">
                UI sẽ tự dò endpoint export khả dụng. Nút nào có link thật thì bật.
              </div>
            </div>
            <div class="vsp-row">
              <a class="vsp-btn" id="btn-exp-html" href="#" target="_blank" rel="noopener">HTML</a>
              <a class="vsp-btn" id="btn-exp-pdf"  href="#" target="_blank" rel="noopener">PDF</a>
              <a class="vsp-btn" id="btn-exp-zip"  href="#" target="_blank" rel="noopener">ZIP</a>
              <a class="vsp-btn" id="btn-open-artindex" href="#" target="_blank" rel="noopener">Artifacts JSON</a>
            </div>
          </div>
          <div class="vsp-muted" style="font-size:12px;margin-top:8px" id="exp-hint">…</div>
        </div>
'''
        t = t.replace(runs_anchor, insert, 1)
    else:
        print("[WARN] cannot inject export panel (runs tab anchor missing)")

    # Expand Data Source tab to show JSON + preview table
    data_anchor = '<section id="tab-data" style="display:none">'
    if data_anchor in t and 'id="ds-statusv2"' not in t:
        repl = data_anchor + r'''
        <!-- === VSP4_DATASOURCE_V1 === -->
'''
        t = t.replace(data_anchor, repl, 1)

        # replace inner of Data Source card minimally by adding extra blocks under existing art-list
        # locate art-list block and append
        if 'id="art-list"' in t and 'id="ds-statusv2"' not in t:
            t = t.replace(
                '  <div id="art-list" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>',
                r'''  <div class="vsp-grid" style="margin-top:10px;gap:12px">
    <div class="vsp-card" style="padding:12px">
      <div style="font-weight:800;margin-bottom:6px">Status V2 JSON</div>
      <div id="ds-statusv2" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>
    </div>

    <div class="vsp-card" style="padding:12px">
      <div style="font-weight:800;margin-bottom:6px">Artifacts index JSON</div>
      <div id="ds-artjson" class="vsp-mono" style="font-size:12px;white-space:pre-wrap"></div>
    </div>

    <div class="vsp-card" style="padding:12px">
      <div class="vsp-row" style="justify-content:space-between">
        <div style="font-weight:800">Findings preview (best-effort)</div>
        <div class="vsp-muted" style="font-size:12px" id="ds-findings-hint">…</div>
      </div>
      <div style="overflow:auto;margin-top:8px">
        <table>
          <thead><tr id="ds-findings-head"></tr></thead>
          <tbody id="ds-findings-body"></tbody>
        </table>
      </div>
    </div>
  </div>'''
            )
        else:
            print("[WARN] cannot inject DataSource JSON blocks (art-list anchor missing)")
else:
    print("[SKIP] template already patched")

tpl.write_text(t, encoding="utf-8")
print("[OK] template updated")

# ---------- Patch JS: add export probing + artifact download probing + datasource render ----------
js = Path("static/js/vsp_ui_4tabs_commercial_v1.js")
j = js.read_text(encoding="utf-8", errors="ignore")

TAG2 = "/* === VSP_UI_4TABS_EXPORT_DS_V1 === */"
if TAG2 in j:
    print("[SKIP] js already patched")
    raise SystemExit(0)

# append helpers near top (after API block) by simple insertion: after "const API = {"
# safer: append at end before boot() call
addon = r'''
/* === VSP_UI_4TABS_EXPORT_DS_V1 === */
async function _vsp_try_head(url){
  try{
    const r = await fetch(url, {method:"HEAD"});
    if (r.ok) return true;
  }catch(e){}
  try{
    const r2 = await fetch(url, {method:"GET", headers: {"Range":"bytes=0-0"}});
    if (r2.ok) return true;
  }catch(e){}
  return false;
}

async function _vsp_probe_first(urls){
  for (const u of urls){
    if (await _vsp_try_head(u)) return u;
  }
  return null;
}

function _vsp_disable_link(a, reason){
  if (!a) return;
  a.href = "#";
  a.style.opacity = "0.45";
  a.style.pointerEvents = "none";
  if (reason) a.title = reason;
}

function _vsp_pretty(obj){
  try { return JSON.stringify(obj, null, 2); } catch(e){ return String(obj); }
}

// try to fetch an artifact file by probing common endpoints
async function _vsp_fetch_artifact_text(rid, path){
  const qp = encodeURIComponent(path);
  const cands = [
    `/api/vsp/run_artifact_v1/${encodeURIComponent(rid)}?path=${qp}`,
    `/api/vsp/run_artifact_get_v1/${encodeURIComponent(rid)}?path=${qp}`,
    `/api/vsp/run_artifacts_get_v1/${encodeURIComponent(rid)}?path=${qp}`,
    `/api/vsp/artifact_get_v1/${encodeURIComponent(rid)}?path=${qp}`,
    `/api/vsp/run_artifact_v1/${encodeURIComponent(rid)}?p=${qp}`,
    `/api/vsp/run_artifact_get_v1/${encodeURIComponent(rid)}?p=${qp}`,
  ];
  for (const u of cands){
    try{
      const r = await fetch(u, {headers: {"Accept":"text/plain,application/json,*/*"}});
      if (!r.ok) continue;
      const txt = await r.text();
      // heuristic: not an HTML error page
      if ((txt||"").trim().startsWith("<!DOCTYPE html") || (txt||"").includes("HTTP_404")) continue;
      return {ok:true, url:u, text:txt};
    }catch(e){}
  }
  return {ok:false, url:null, text:null};
}

function _vsp_parse_csv_preview(csvText, limitRows=50){
  const lines = (csvText||"").split(/\r?\n/).filter(x=>x.trim().length>0);
  if (!lines.length) return {cols:[], rows:[]};
  // naive CSV split (good enough for preview)
  const split = (s)=> {
    const out=[]; let cur=""; let q=false;
    for (let i=0;i<s.length;i++){
      const ch=s[i];
      if (ch === '"' ){ q = !q; continue; }
      if (ch === "," && !q){ out.push(cur); cur=""; continue; }
      cur+=ch;
    }
    out.push(cur);
    return out.map(x=>x.trim());
  };
  const cols = split(lines[0]).slice(0,40);
  const rows = [];
  for (let i=1;i<lines.length && rows.length<limitRows;i++){
    rows.push(split(lines[i]).slice(0,40));
  }
  return {cols, rows};
}

function _vsp_render_findings_table(cols, rows){
  const head = document.getElementById("ds-findings-head");
  const body = document.getElementById("ds-findings-body");
  if (!head || !body) return;

  head.innerHTML = "";
  body.innerHTML = "";

  cols.slice(0,14).forEach(c=>{
    const th = document.createElement("th");
    th.textContent = c;
    head.appendChild(th);
  });

  rows.slice(0,80).forEach(r=>{
    const tr = document.createElement("tr");
    cols.slice(0,14).forEach((_,i)=>{
      const td = document.createElement("td");
      td.textContent = (r[i] ?? "");
      tr.appendChild(td);
    });
    body.appendChild(tr);
  });
}

async function _vsp_setup_export_links(selectedRid){
  const aHtml = document.getElementById("btn-exp-html");
  const aPdf  = document.getElementById("btn-exp-pdf");
  const aZip  = document.getElementById("btn-exp-zip");
  const aArt  = document.getElementById("btn-open-artindex");
  const hint  = document.getElementById("exp-hint");

  if (!aHtml && !aPdf && !aZip) return;

  if (!selectedRid){
    _vsp_disable_link(aHtml,"no run");
    _vsp_disable_link(aPdf,"no run");
    _vsp_disable_link(aZip,"no run");
    _vsp_disable_link(aArt,"no run");
    if (hint) hint.textContent = "no selected run";
    return;
  }

  // artifacts index always exists
  if (aArt){
    aArt.href = `/api/vsp/run_artifacts_index_v1/${encodeURIComponent(selectedRid)}`;
    aArt.style.opacity = "1";
    aArt.style.pointerEvents = "auto";
  }

  // probe export endpoints (several shapes)
  const mk = (fmt)=>[
    `/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?fmt=${fmt}`,
    `/api/vsp/run_export_v3/${encodeURIComponent(selectedRid)}?format=${fmt}`,
    `/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&fmt=${fmt}`,
    `/api/vsp/run_export_v3?run_id=${encodeURIComponent(selectedRid)}&fmt=${fmt}`,
    `/api/vsp/run_export_v3?rid=${encodeURIComponent(selectedRid)}&format=${fmt}`,
  ];

  const uHtml = await _vsp_probe_first(mk("html"));
  const uPdf  = await _vsp_probe_first(mk("pdf"));
  const uZip  = await _vsp_probe_first(mk("zip"));

  if (uHtml){ aHtml.href=uHtml; aHtml.style.opacity="1"; aHtml.style.pointerEvents="auto"; }
  else _vsp_disable_link(aHtml,"export html not available");

  if (uPdf){ aPdf.href=uPdf; aPdf.style.opacity="1"; aPdf.style.pointerEvents="auto"; }
  else _vsp_disable_link(aPdf,"export pdf not available");

  if (uZip){ aZip.href=uZip; aZip.style.opacity="1"; aZip.style.pointerEvents="auto"; }
  else _vsp_disable_link(aZip,"export zip not available");

  if (hint){
    hint.textContent = `rid=${selectedRid} • export: ${uHtml?'HTML':'-'} ${uPdf?'PDF':'-'} ${uZip?'ZIP':'-'}`
  }
}

async function _vsp_render_datasource(rid, statusV2Obj){
  const boxS = document.getElementById("ds-statusv2");
  const boxA = document.getElementById("ds-artjson");
  const hint = document.getElementById("ds-findings-hint");

  if (boxS) boxS.textContent = _vsp_pretty(statusV2Obj || {});
  if (!rid) return;

  // artifacts index JSON
  let art = null;
  try{
    art = await fetchJSON(`/api/vsp/run_artifacts_index_v1/${encodeURIComponent(rid)}`);
    if (boxA) boxA.textContent = _vsp_pretty(art);
  }catch(e){
    if (boxA) boxA.textContent = String(e);
    if (hint) hint.textContent = "cannot load artifacts index";
    return;
  }

  // find candidate findings files from artifacts list
  const items = art.items || art.artifacts || art.files || [];
  const paths = items.map(x => (typeof x === "string") ? x : (x.path || x.name || "")).filter(Boolean);

  const pick = (needle)=> paths.find(p => p.toLowerCase().includes(needle));
  const csvPath = pick("findings_unified.csv") || pick("findings.csv") || pick("findings_unified");
  const jsonPath = pick("findings_unified.json") || pick("findings.json");

  if (!csvPath && !jsonPath){
    if (hint) hint.textContent = "no findings_unified.* in artifacts index";
    return;
  }

  // try csv first for table preview
  if (csvPath){
    if (hint) hint.textContent = `trying csv: ${csvPath}`;
    const r = await _vsp_fetch_artifact_text(rid, csvPath);
    if (r.ok){
      const pv = _vsp_parse_csv_preview(r.text, 60);
      _vsp_render_findings_table(pv.cols, pv.rows);
      if (hint) hint.textContent = `preview from CSV ✓ via ${r.url}`;
      return;
    }
  }

  // fallback json
  if (jsonPath){
    if (hint) hint.textContent = `trying json: ${jsonPath}`;
    const r = await _vsp_fetch_artifact_text(rid, jsonPath);
    if (r.ok){
      let obj = null;
      try{ obj = JSON.parse(r.text); }catch(e){ obj=null; }
      if (obj && Array.isArray(obj.items)) obj = obj.items;
      // render columns from first item keys
      const rows = Array.isArray(obj) ? obj.slice(0,60) : [];
      const cols = rows[0] ? Object.keys(rows[0]).slice(0,14) : [];
      const tableRows = rows.map(o => cols.map(c => (o && o[c] !== undefined) ? String(o[c]) : ""));
      _vsp_render_findings_table(cols, tableRows);
      if (hint) hint.textContent = `preview from JSON ✓ via ${r.url}`;
      return;
    }
  }

  if (hint) hint.textContent = "cannot fetch findings file (no artifact download endpoint found)";
}
'''

# inject addon before boot() definition (find "async function boot(){")
m = re.search(r'\n\s*async function boot\(\)\{', j)
if not m:
    raise SystemExit("[ERR] cannot find boot() in JS to inject addon")

j2 = j[:m.start()] + "\n" + addon + "\n" + j[m.start():]

# Now hook into loadOne(rid) to call export + datasource
# find function loadOne and after status loaded, call _vsp_setup_export_links and _vsp_render_datasource
pat = r'async function loadOne\(rid\)\{\s*if \(!rid\) return;\s*let s = null;[\s\S]*?if \(!s\)\{\s*[\s\S]*?return;\s*\}\s*updateKpis\(s\);\s*renderGateByTool\(s\);\s*updateMeta\(s\);\s*await renderArtifacts\(rid\);\s*\}'
m2 = re.search(pat, j2)
if not m2:
    print("[WARN] cannot locate loadOne block exactly; will do a softer insertion")
    # soft insertion: after 'await renderArtifacts(rid);'
    j2 = re.sub(r'await renderArtifacts\(rid\);\s*', 'await renderArtifacts(rid);\n    await _vsp_setup_export_links(rid);\n    await _vsp_render_datasource(rid, s);\n', j2, count=1)
else:
    # replace with extended version
    repl = r'''async function loadOne(rid){
    if (!rid) return;
    let s = null;
    try { s = await fetchJSON(API.statusV2(rid)); } catch(e){ s = null; }
    if (!s){
      setText("run-meta", "cannot load status_v2");
      return;
    }
    updateKpis(s);
    renderGateByTool(s);
    updateMeta(s);
    await renderArtifacts(rid);
    await _vsp_setup_export_links(rid);
    await _vsp_render_datasource(rid, s);
  }'''
    j2 = j2[:m2.start()] + repl + j2[m2.end():]

# also hook into loadRuns() end: set export links for selected run once picker is filled
j2 = re.sub(r'if \(rid\) await loadOne\(rid\);\s*\}', 'if (rid) await loadOne(rid);\n    await _vsp_setup_export_links(rid);\n  }', j2, count=1)

js.write_text(j2, encoding="utf-8")
print("[OK] JS updated")
PY

python3 -m py_compile vsp_demo_app.py >/dev/null
rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== SMOKE =="
curl -sS -o /dev/null -w "GET /vsp4 HTTP=%{http_code}\n" http://127.0.0.1:8910/vsp4
echo "[OK] open: http://127.0.0.1:8910/vsp4"
echo "[HINT] click Runs & Reports -> Export panel, Data Source -> JSON + findings preview"
