#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] find template that contains Top findings =="
TPL="$(python3 - <<'PY'
from pathlib import Path
import re

troot = Path("templates")
cands = []
if troot.is_dir():
  for p in sorted(troot.rglob("*.html")):
    s = p.read_text(encoding="utf-8", errors="replace")
    if re.search(r"Top\s+findings", s, re.I) and re.search(r"Load\s+top\s+findings", s, re.I):
      cands.append(str(p))
print(cands[0] if cands else "")
PY
)"
[ -n "${TPL:-}" ] || { echo "[ERR] cannot locate template containing Top findings + Load top findings"; exit 2; }
echo "[INFO] TPL=$TPL"

echo "== [1] patch template: add stable IDs (button/tbody/status) =="
cp -f "$TPL" "${TPL}.bak_topfind_ids_${TS}"
python3 - <<'PY'
from pathlib import Path
import re

tpl = Path(__import__("os").environ["TPL"])
s = tpl.read_text(encoding="utf-8", errors="replace")

# 1) button id
# add id="vsp_btn_topfind" if missing
def add_btn_id(m):
  tag = m.group(0)
  if re.search(r'\bid\s*=\s*["\']vsp_btn_topfind["\']', tag, re.I):
    return tag
  # insert id before closing '>'
  return re.sub(r'<button\b', '<button id="vsp_btn_topfind"', tag, count=1, flags=re.I)

s2 = re.sub(r'<button\b[^>]*>\s*Load\s+top\s+findings\s*\(25\)\s*</button>', add_btn_id, s, flags=re.I)

# 2) tbody id: try to locate the table under "Top findings" block and add id to first <tbody> after that
if 'id="vsp_tb_topfind"' not in s2:
  # heuristic: find the first <tbody> that appears after "Top findings"
  idx = re.search(r'Top\s+findings', s2, re.I)
  if idx:
    start = idx.start()
    after = s2[start:]
    m = re.search(r'<tbody\b[^>]*>', after, re.I)
    if m:
      tb_tag = m.group(0)
      if 'id=' not in tb_tag.lower():
        tb_new = tb_tag[:-1] + ' id="vsp_tb_topfind">'
      else:
        # has id but not ours, append data-attr for safety
        tb_new = tb_tag[:-1] + ' data-vsp="topfind" id="vsp_tb_topfind">'
      after2 = after[:m.start()] + tb_new + after[m.end():]
      s2 = s2[:start] + after2

# 3) status cell id: find "Not loaded" cell and tag it
def add_status_id(m):
  tag = m.group(0)
  if re.search(r'\bid\s*=\s*["\']vsp_topfind_status["\']', tag, re.I):
    return tag
  return re.sub(r'<td\b', '<td id="vsp_topfind_status"', tag, count=1, flags=re.I)

s3 = re.sub(r'<td\b[^>]*>\s*Not\s+loaded\s*</td>', add_status_id, s2, flags=re.I)

tpl.write_text(s3, encoding="utf-8")
print("[OK] template patched ids: vsp_btn_topfind / vsp_tb_topfind / vsp_topfind_status")
PY

echo "== [2] patch JS: force bind by IDs + 3-level fallback =="
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
cp -f "$JS" "${JS}.bak_topfind_force_ids_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_TOPFIND_FORCE_IDS_BIND_V1"

if MARK in s:
  print("[SKIP] already patched:", MARK)
else:
  block = textwrap.dedent(r"""
  /* VSP_P0_TOPFIND_FORCE_IDS_BIND_V1
     Hard guarantee:
       - bind button by #vsp_btn_topfind (clone to kill old handlers)
       - render tbody by #vsp_tb_topfind
       - status by #vsp_topfind_status
       - data fallback: CSV -> SARIF -> findings_unified.json
  */
  (()=> {
    if (window.__vsp_p0_topfind_force_ids_v1) return;
    window.__vsp_p0_topfind_force_ids_v1 = true;

    const RID_LATEST = "/api/vsp/rid_latest_gate_root";
    const PATH_CSV   = "reports/findings_unified.csv";
    const PATH_SARIF = "reports/findings_unified.sarif";
    const PATH_JSON  = "findings_unified.json";

    const SEV_W = {CRITICAL:600,HIGH:500,MEDIUM:400,LOW:300,INFO:200,TRACE:100};
    const norm = (v)=> (v==null ? "" : String(v)).trim();
    const upper = (v)=> norm(v).toUpperCase();

    function normSev(v){
      const x = upper(v);
      if (SEV_W[x]) return x;
      if (x==="ERROR") return "HIGH";
      if (x==="WARNING"||x==="WARN") return "MEDIUM";
      if (x==="NOTE") return "LOW";
      if (x==="DEBUG") return "TRACE";
      return x || "INFO";
    }

    async function getRidLatest(){
      const r = await fetch(RID_LATEST, {cache:"no-store"});
      if (!r.ok) throw new Error("rid_latest_gate_root http " + r.status);
      const j = await r.json();
      return j && j.rid ? String(j.rid) : "";
    }
    function rfUrl(rid, path){
      return `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
    }

    function elStatus(){ return document.getElementById("vsp_topfind_status"); }
    function elBtn(){ return document.getElementById("vsp_btn_topfind"); }
    function elTbody(){ return document.getElementById("vsp_tb_topfind"); }

    function setStatus(msg){
      const e = elStatus();
      if (e) e.textContent = msg;
    }
    function renderRows(items){
      const tb = elTbody();
      if (!tb) throw new Error("missing #vsp_tb_topfind");
      tb.innerHTML = "";
      for (const it of items){
        const tr = document.createElement("tr");
        const tdSev = document.createElement("td");
        const tdTool = document.createElement("td");
        const tdTitle = document.createElement("td");
        const tdLoc = document.createElement("td");
        tdSev.textContent = it.severity || "";
        tdTool.textContent = it.tool || "";
        tdTitle.textContent = it.title || "";
        tdLoc.textContent = (it.file ? it.file : "") + (it.line ? (":" + it.line) : "");
        tr.appendChild(tdSev); tr.appendChild(tdTool); tr.appendChild(tdTitle); tr.appendChild(tdLoc);
        tb.appendChild(tr);
      }
    }
    function takeTopN(items, n){
      items.sort((a,b)=> (SEV_W[upper(b.severity)]||0) - (SEV_W[upper(a.severity)]||0));
      if (items.length>n) items.length=n;
      return items;
    }

    // CSV parse (quotes supported)
    function parseCSV(text, maxRows=8000){
      text = String(text || "").replace(/\r\n/g,"\n").replace(/\r/g,"\n");
      const rows = [];
      let row = [], cur = "", inQ=false;
      for (let i=0;i<text.length;i++){
        const ch = text[i];
        if (inQ){
          if (ch === '"'){
            if (text[i+1] === '"'){ cur += '"'; i++; continue; }
            inQ = false; continue;
          }
          cur += ch; continue;
        }
        if (ch === '"'){ inQ=true; continue; }
        if (ch === ','){ row.push(cur); cur=""; continue; }
        if (ch === '\n'){
          row.push(cur); cur="";
          if (!(row.length===1 && row[0]==="")) rows.push(row);
          row=[];
          if (rows.length>=maxRows) break;
          continue;
        }
        cur += ch;
      }
      if (cur.length || row.length){
        row.push(cur);
        if (!(row.length===1 && row[0]==="")) rows.push(row);
      }
      return rows;
    }

    async function loadFromCSV(rid, limit){
      const r = await fetch(rfUrl(rid, PATH_CSV), {cache:"no-store"});
      if (!r.ok) throw new Error("CSV http " + r.status);
      const text = await r.text();
      const logical = text.replace(/\r\n/g,"\n").replace(/\r/g,"\n").split("\n").filter(x=>x.trim()!=="");
      if (logical.length <= 1) throw new Error("CSV header only");
      const rows = parseCSV(text);
      if (rows.length <= 1) throw new Error("CSV rows empty");
      const header = rows[0].map(x=>norm(x));
      const idx = {};
      for (let i=0;i<header.length;i++) idx[header[i].toLowerCase()] = i;
      const get = (row, name)=> {
        const i = idx[name];
        if (i==null) return "";
        return row[i]==null ? "" : String(row[i]);
      };
      const items=[];
      for (let i=1;i<rows.length;i++){
        const row=rows[i];
        if (!row || row.length<2) continue;
        const sev = normSev(get(row,"severity"));
        items.push({
          severity: sev,
          tool: norm(get(row,"tool")),
          title: norm(get(row,"title")) || norm(get(row,"message")) || norm(get(row,"rule_id")),
          file: norm(get(row,"file")),
          line: norm(get(row,"line")),
        });
      }
      if (!items.length) throw new Error("CSV yielded 0 items");
      return takeTopN(items, limit);
    }

    function mapSarifLevelToSev(level){
      const lv = (level||"").toLowerCase();
      if (lv === "error") return "HIGH";
      if (lv === "warning") return "MEDIUM";
      if (lv === "note") return "LOW";
      return "INFO";
    }

    async function loadFromSarif(rid, limit){
      const r = await fetch(rfUrl(rid, PATH_SARIF), {cache:"no-store"});
      if (!r.ok) throw new Error("SARIF http " + r.status);
      const j = await r.json();
      const items=[];
      const runs = (j && j.runs) ? j.runs : [];
      for (const run of runs){
        const toolName = norm(run?.tool?.driver?.name) || "";
        const results = run?.results || [];
        for (const res of results){
          const sev = normSev(res?.properties?.severity) || mapSarifLevelToSev(res?.level);
          const msg = norm(res?.message?.text) || norm(res?.message?.markdown) || norm(res?.ruleId) || "Finding";
          const loc0 = res?.locations?.[0]?.physicalLocation;
          const file = norm(loc0?.artifactLocation?.uri) || "";
          const line = String(loc0?.region?.startLine || "").trim();
          items.push({
            severity: sev,
            tool: norm(res?.properties?.tool) || toolName || norm(res?.ruleId) || "",
            title: msg,
            file, line,
          });
        }
      }
      if (!items.length) throw new Error("SARIF yielded 0 items");
      return takeTopN(items, limit);
    }

    function pick(obj, keys){
      for (const k of keys){
        const v = obj?.[k];
        if (v!=null && String(v).trim()!=="") return v;
      }
      return "";
    }

    async function loadFromUnifiedJson(rid, limit){
      const r = await fetch(rfUrl(rid, PATH_JSON), {cache:"no-store"});
      if (!r.ok) throw new Error("JSON http " + r.status);
      const j = await r.json();
      const arr = Array.isArray(j) ? j : (Array.isArray(j?.findings) ? j.findings : []);
      if (!arr.length) throw new Error("JSON findings empty");
      const items=[];
      for (const f of arr){
        const sev = normSev(pick(f, ["severity","normalized_severity"]) || pick(f?.meta, ["severity"]) || pick(f?.properties, ["severity"]));
        const tool = norm(pick(f, ["tool","source","engine"]) || pick(f?.meta, ["tool"]) || pick(f?.properties, ["tool"]));
        const title = norm(pick(f, ["title","message","rule_id","ruleId","id"]) || pick(f?.meta, ["title","message"]));
        const file = norm(pick(f, ["file","path"]) || pick(f?.location, ["file","path"]) || pick(f?.meta, ["file","path"]));
        const line = norm(pick(f, ["line"]) || pick(f?.location, ["line","startLine"]) || pick(f?.meta, ["line","startLine"]));
        if (!title && !file) continue;
        items.push({severity: sev || "INFO", tool, title: title || "Finding", file, line});
      }
      if (!items.length) throw new Error("JSON yielded 0 items");
      return takeTopN(items, limit);
    }

    async function loadTopFindings(limit=25){
      const rid = await getRidLatest();
      if (!rid) throw new Error("RID empty");
      setStatus("Loading…");
      console.log("[VSP][TOPFIND_IDS_V1] start rid=", rid);

      try{
        const a = await loadFromCSV(rid, limit);
        renderRows(a); setStatus("Loaded: "+a.length+" (CSV)");
        console.log("[VSP][TOPFIND_IDS_V1] ok via CSV", a.length);
        return;
      } catch(e1){
        console.warn("[VSP][TOPFIND_IDS_V1] CSV failed:", e1?.message||e1);
      }

      try{
        const b = await loadFromSarif(rid, limit);
        renderRows(b); setStatus("Loaded: "+b.length+" (SARIF)");
        console.log("[VSP][TOPFIND_IDS_V1] ok via SARIF", b.length);
        return;
      } catch(e2){
        console.warn("[VSP][TOPFIND_IDS_V1] SARIF failed:", e2?.message||e2);
      }

      const c = await loadFromUnifiedJson(rid, limit);
      renderRows(c); setStatus("Loaded: "+c.length+" (JSON)");
      console.log("[VSP][TOPFIND_IDS_V1] ok via JSON", c.length);
    }

    function bind(){
      const btn = elBtn();
      if (!btn || !btn.parentNode) return false;

      // kill older handlers
      const b2 = btn.cloneNode(true);
      btn.parentNode.replaceChild(b2, btn);

      b2.addEventListener("click", async (ev)=> {
        ev.preventDefault();
        ev.stopPropagation();
        ev.stopImmediatePropagation?.();
        const old = b2.textContent;
        b2.disabled = true;
        b2.textContent = "Loading…";
        try{
          await loadTopFindings(25);
        }catch(e){
          console.warn("[VSP][TOPFIND_IDS_V1] failed:", e);
          setStatus("Load failed: " + (e?.message || String(e)));
        }finally{
          b2.disabled = false;
          b2.textContent = old || "Load top findings (25)";
        }
      }, {capture:true});

      console.log("[VSP][TOPFIND_IDS_V1] bound OK (button cloned last)");
      return true;
    }

    function start(){
      bind();
      let tries=0;
      const t=setInterval(()=> { tries++; bind(); if (tries>=10) clearInterval(t); }, 800);
      const obs = new MutationObserver(()=> bind());
      obs.observe(document.documentElement, {subtree:true, childList:true});
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
    else setTimeout(start, 0);
  })();
  """)
  p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
  print("[OK] appended:", MARK)
PY

node --check static/js/vsp_dash_only_v1.js
systemctl restart "$SVC" 2>/dev/null || true

echo "== [3] quick backend probes =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "[INFO] RID=$RID"

python3 - <<PY
import urllib.request, json
base="$BASE"
rid="$RID"
def get(url):
  with urllib.request.urlopen(url) as r: return r.read()
def bytes_of(path):
  u=f"{base}/api/vsp/run_file_allow?rid={rid}&path={path}"
  try:
    b=get(u); return len(b), b[:160]
  except Exception as e:
    return -1, str(e).encode()

for path in ["reports/findings_unified.csv","reports/findings_unified.sarif","findings_unified.json"]:
  n, head = bytes_of(path)
  print("path=",path,"bytes=",n,"head=",head.decode("utf-8","replace").replace("\n","\\n")[:160])
PY

echo "[DONE] Open /vsp5 then HARD refresh (Ctrl+Shift+R). Click Load top findings (25)."
echo "       Console should show: [VSP][TOPFIND_IDS_V1] ok via (CSV|SARIF|JSON)"
