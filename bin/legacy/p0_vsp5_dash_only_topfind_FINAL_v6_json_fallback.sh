#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json;print(json.load(sys.stdin)["rid"])')"
echo "[INFO] RID=$RID"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_FINAL_v6_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_FINAL_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_DASH_ONLY_TOPFIND_FINAL_V6_JSON_FALLBACK"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_DASH_ONLY_TOPFIND_FINAL_V6_JSON_FALLBACK
       FINAL: rebinding guard + 3-level fallback:
         1) reports/findings_unified.csv (must have >1 logical line)
         2) reports/findings_unified.sarif (must yield >0 results)
         3) findings_unified.json (meta+findings)  <-- NEW
    */
    (()=> {
      if (window.__vsp_p0_dash_only_topfind_final_v6) return;
      window.__vsp_p0_dash_only_topfind_final_v6 = true;

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
        // common variants
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

      // ===== DOM helpers =====
      function findTopFindingsCard(){
        const nodes = Array.from(document.querySelectorAll("div,section,article"));
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (t.includes("top findings")) return n;
        }
        return null;
      }
      function findButton(){
        const btns = Array.from(document.querySelectorAll("button"));
        for (const b of btns){
          const t = (b.textContent || "").toLowerCase().replace(/\s+/g," ").trim();
          if (t.includes("load top findings")) return b;
        }
        return null;
      }
      function findTableTbody(){
        const card = findTopFindingsCard();
        if (card){
          const tb = card.querySelector("tbody");
          if (tb) return tb;
        }
        return document.querySelector("tbody");
      }
      function setStatus(msg){
        const card = findTopFindingsCard();
        if (!card) return;
        const cells = Array.from(card.querySelectorAll("td,div,span,p"));
        for (const c of cells){
          const t = (c.textContent || "").toLowerCase().trim();
          if (t === "not loaded" || t === "loading..." || t === "loading…" || t.startsWith("load failed") || t.startsWith("loaded:")){
            c.textContent = msg;
            return;
          }
        }
      }
      function renderRows(items){
        const tb = findTableTbody();
        if (!tb) throw new Error("cannot find <tbody> for top findings");
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

      // ===== CSV parsing (quotes supported) =====
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
        const url = rfUrl(rid, PATH_CSV);
        const r = await fetch(url, {cache:"no-store"});
        if (!r.ok) throw new Error("CSV http " + r.status);
        const text = await r.text();
        const logicalLines = text.replace(/\r\n/g,"\n").replace(/\r/g,"\n").split("\n").filter(x=>x.trim()!=="");
        if (logicalLines.length <= 1) throw new Error("CSV has header only");

        const rows = parseCSV(text);
        if (rows.length <= 1) throw new Error("CSV parse empty rows");
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
          if (!sev) continue;
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

      // ===== SARIF fallback =====
      function mapSarifLevelToSev(level){
        const lv = (level||"").toLowerCase();
        if (lv === "error") return "HIGH";
        if (lv === "warning") return "MEDIUM";
        if (lv === "note") return "LOW";
        return "INFO";
      }

      async function loadFromSarif(rid, limit){
        const url = rfUrl(rid, PATH_SARIF);
        const r = await fetch(url, {cache:"no-store"});
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
              file,
              line,
            });
          }
        }
        if (!items.length) throw new Error("SARIF yielded 0 items");
        return takeTopN(items, limit);
      }

      // ===== JSON fallback (findings_unified.json) =====
      function pick(obj, keys){
        for (const k of keys){
          const v = obj?.[k];
          if (v!=null && String(v).trim()!=="") return v;
        }
        return "";
      }

      async function loadFromUnifiedJson(rid, limit){
        const url = rfUrl(rid, PATH_JSON);
        const r = await fetch(url, {cache:"no-store"});
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
        console.log("[VSP][DASH_ONLY] topfind FINAL v6 start rid=", rid);

        try{
          const items = await loadFromCSV(rid, limit);
          renderRows(items);
          setStatus("Loaded: " + items.length + " (CSV)");
          console.log("[VSP][DASH_ONLY] topfind FINAL v6 ok via CSV", items.length);
          return;
        }catch(e1){
          console.warn("[VSP][DASH_ONLY] CSV failed:", e1?.message || e1);
        }

        try{
          const items2 = await loadFromSarif(rid, limit);
          renderRows(items2);
          setStatus("Loaded: " + items2.length + " (SARIF)");
          console.log("[VSP][DASH_ONLY] topfind FINAL v6 ok via SARIF", items2.length);
          return;
        }catch(e2){
          console.warn("[VSP][DASH_ONLY] SARIF failed:", e2?.message || e2);
        }

        const items3 = await loadFromUnifiedJson(rid, limit);
        renderRows(items3);
        setStatus("Loaded: " + items3.length + " (JSON)");
        console.log("[VSP][DASH_ONLY] topfind FINAL v6 ok via JSON", items3.length);
      }

      // ===== FINAL rebind (always win) =====
      function bindFinal(){
        const btn = findButton();
        if (!btn || !btn.parentNode) return false;

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
            console.warn("[VSP][DASH_ONLY] topfind FINAL v6 failed:", e);
            setStatus("Load failed: " + (e?.message || String(e)));
          }finally{
            b2.disabled = false;
            b2.textContent = old || "Load top findings (25)";
          }
        }, {capture:true});

        console.log("[VSP][DASH_ONLY] topfind FINAL v6 bound (button cloned last)");
        return true;
      }

      function start(){
        bindFinal();
        let tries=0;
        const t=setInterval(()=> {
          tries++; bindFinal();
          if (tries>=10) clearInterval(t);
        }, 800);

        const obs = new MutationObserver(()=> bindFinal());
        obs.observe(document.documentElement, {subtree:true, childList:true});
      }

      if (document.readyState === "loading"){
        document.addEventListener("DOMContentLoaded", start);
      } else {
        setTimeout(start, 0);
      }
    })();
    """)

    p.write_text(s + "\n\n" + block + "\n", encoding="utf-8")
    print("[OK] appended:", MARK)
PY

node --check "$JS"
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R), then click: Load top findings (25)."
