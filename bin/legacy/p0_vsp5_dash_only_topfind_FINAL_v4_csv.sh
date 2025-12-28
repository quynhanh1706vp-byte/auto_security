#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_FINAL_v4_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_FINAL_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_DASH_ONLY_TOPFIND_FINAL_V4_CSV"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    block = textwrap.dedent(r"""
    /* VSP_P0_DASH_ONLY_TOPFIND_FINAL_V4_CSV
       FINAL override: always runs last, re-clone button to remove ALL previous listeners,
       fetch CSV (allowed) and render Top findings table.
    */
    (()=> {
      if (window.__vsp_p0_dash_only_topfind_final_v4_csv) return;
      window.__vsp_p0_dash_only_topfind_final_v4_csv = true;

      const RID_LATEST = "/api/vsp/rid_latest_gate_root";
      const CSV_PATH = "reports/findings_unified.csv";

      const SEV_ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const SEV_W = {CRITICAL: 600, HIGH: 500, MEDIUM: 400, LOW: 300, INFO: 200, TRACE: 100};

      const norm = (v)=> (v==null ? "" : String(v)).trim();
      const upper = (v)=> norm(v).toUpperCase();

      async function getRidLatest(){
        const r = await fetch(RID_LATEST, {cache:"no-store"});
        if (!r.ok) throw new Error("rid_latest_gate_root http " + r.status);
        const j = await r.json();
        return j && j.rid ? String(j.rid) : "";
      }

      function csvUrl(rid){
        return `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(CSV_PATH)}`;
      }

      // Minimal CSV parser w/ quotes
      function parseCSV(text, maxRows=4000){
        const rows = [];
        let row = [];
        let cur = "";
        let i = 0;
        let inQ = false;

        // normalize newlines
        text = String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");

        while (i < text.length){
          const ch = text[i];

          if (inQ){
            if (ch === '"'){
              // escaped quote?
              if (text[i+1] === '"'){ cur += '"'; i += 2; continue; }
              inQ = false; i += 1; continue;
            }
            cur += ch; i += 1; continue;
          }

          if (ch === '"'){ inQ = true; i += 1; continue; }

          if (ch === ','){
            row.push(cur); cur = ""; i += 1; continue;
          }

          if (ch === '\n'){
            row.push(cur); cur = ""; i += 1;
            // ignore empty last line
            if (!(row.length === 1 && row[0] === "")) rows.push(row);
            row = [];
            if (rows.length >= maxRows) break;
            continue;
          }

          cur += ch; i += 1;
        }

        if (cur.length || row.length){
          row.push(cur);
          if (!(row.length === 1 && row[0] === "")) rows.push(row);
        }
        return rows;
      }

      function findTopFindingsCard(){
        // locate by heading text "Top findings"
        const nodes = Array.from(document.querySelectorAll("div,section,article"));
        for (const n of nodes){
          const t = (n.textContent || "").toLowerCase();
          if (t.includes("top findings")) return n;
        }
        return null;
      }

      function findButton(){
        // robust: any button containing "Load top findings"
        const btns = Array.from(document.querySelectorAll("button"));
        for (const b of btns){
          const t = (b.textContent || "").toLowerCase().replace(/\s+/g," ").trim();
          if (t.includes("load top findings")) return b;
        }
        return null;
      }

      function findTableTbody(){
        // prefer tbody inside the "Top findings" area
        const card = findTopFindingsCard();
        if (card){
          const tb = card.querySelector("tbody");
          if (tb) return tb;
        }
        // fallback: first tbody on page
        return document.querySelector("tbody");
      }

      function setStatus(msg){
        // try to place status inside top findings card
        const card = findTopFindingsCard();
        if (!card) return;
        // find a "Not loaded" cell and replace its text
        const cells = Array.from(card.querySelectorAll("td,div,span,p"));
        for (const c of cells){
          const t = (c.textContent || "").toLowerCase().trim();
          if (t === "not loaded" || t === "loading..." || t === "loading…"){
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

          const loc = [];
          if (it.file) loc.push(it.file);
          if (it.line) loc.push(":" + it.line);
          tdLoc.textContent = loc.join("");

          tr.appendChild(tdSev);
          tr.appendChild(tdTool);
          tr.appendChild(tdTitle);
          tr.appendChild(tdLoc);
          tb.appendChild(tr);
        }
      }

      async function loadTopFindings(limit=25){
        const rid = await getRidLatest();
        if (!rid) throw new Error("RID empty");
        const url = csvUrl(rid);

        setStatus("Loading…");

        const r = await fetch(url, {cache:"no-store"});
        if (!r.ok) throw new Error("fetch CSV http " + r.status);

        const text = await r.text();
        const rows = parseCSV(text, 8000);
        if (!rows.length) throw new Error("CSV empty");

        const header = rows[0].map(x => norm(x));
        const idx = {}
        for (let i=0;i<header.length;i++){
          const k = header[i].toLowerCase();
          idx[k] = i
        }

        function getcol(row, name){
          const i = idx[name];
          if (i==null) return "";
          return row[i] == null ? "" : String(row[i]);
        }

        // keep best N by severity weight
        const best = [];
        function pushBest(it){
          best.push(it);
          best.sort((a,b)=> (SEV_W[upper(b.severity)]||0) - (SEV_W[upper(a.severity)]||0));
          if (best.length > limit) best.length = limit;
        }

        for (let i=1;i<rows.length;i++){
          const row = rows[i];
          if (!row || row.length < 2) continue;

          const sev = upper(getcol(row, "severity"));
          if (!sev) continue;

          const it = {
            severity: sev,
            tool: norm(getcol(row, "tool")),
            title: norm(getcol(row, "title")) || norm(getcol(row, "message")) || norm(getcol(row, "rule_id")),
            file: norm(getcol(row, "file")),
            line: norm(getcol(row, "line")),
          };
          pushBest(it);
        }

        renderRows(best);
        setStatus("Loaded: " + best.length + " items");
        console.log("[VSP][DASH_ONLY] topfind FINAL v4 loaded:", best.length);
      }

      function bindFinal(){
        const btn = findButton();
        if (!btn || !btn.parentNode) return false;

        // Clone LAST to remove all old listeners
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
            console.warn("[VSP][DASH_ONLY] topfind FINAL v4 failed:", e);
            setStatus("Load failed: " + (e && e.message ? e.message : String(e)));
          }finally{
            b2.disabled = false;
            b2.textContent = old || "Load top findings (25)";
          }
        }, {capture:true});

        console.log("[VSP][DASH_ONLY] topfind FINAL v4 bound (button cloned last)");
        return true;
      }

      function start(){
        // bind now
        if (bindFinal()) return;

        // retry a few times for slow DOM
        let tries = 0;
        const t = setInterval(()=> {
          tries++;
          if (bindFinal() || tries >= 10) clearInterval(t);
        }, 600);
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

echo "== [1] node --check after patch =="
node --check "$JS"
echo "[OK] node --check passed"

echo "== [2] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R) then click: Load top findings (25)."
