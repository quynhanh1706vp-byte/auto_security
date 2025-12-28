#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_topfind_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P0_DASH_ONLY_LOAD_TOP_FINDINGS_V1"

if MARK in s:
    print("[SKIP] already patched:", MARK)
else:
    patch = textwrap.dedent(r"""
    /* VSP_P0_DASH_ONLY_LOAD_TOP_FINDINGS_V1
       Hook button "Load top findings (25)" to fetch findings_unified.json on-demand and render table.
       - NO auto-fetch heavy data
       - Cache per RID
       - Robust DOM selectors (text-based)
    */
    (()=> {
      if (window.__vsp_p0_dash_only_load_top_findings_v1) return;
      window.__vsp_p0_dash_only_load_top_findings_v1 = true;

      const SEV_ORDER = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
      const SEV_W = {CRITICAL: 600, HIGH: 500, MEDIUM: 400, LOW: 300, INFO: 200, TRACE: 100};

      const cache = window.__vsp_dash_only_cache_findings || (window.__vsp_dash_only_cache_findings = {});

      const norm = (v)=> (v==null ? "" : String(v)).trim();
      const normSev = (v)=>{
        const x = norm(v).toUpperCase();
        if (!x) return "";
        // common aliases
        if (x === "CRIT") return "CRITICAL";
        if (x === "WARN") return "MEDIUM";
        if (x === "WARNING") return "MEDIUM";
        return SEV_ORDER.includes(x) ? x : x;
      };

      const pick = (obj, keys)=>{
        if (!obj || typeof obj !== "object") return "";
        for (const k of keys){
          if (obj[k] != null) return obj[k];
        }
        return "";
      };

      const pickTool = (f)=>{
        return norm(
          pick(f, ["tool","engine","scanner","source","detector","product","provider"]) ||
          pick(f?.meta, ["tool","engine","scanner","source"]) ||
          pick(f?.extra, ["tool","engine","scanner","source"])
        ) || "UNKNOWN";
      };

      const pickSeverity = (f)=>{
        return normSev(
          pick(f, ["severity","sev","level","priority"]) ||
          pick(f?.meta, ["severity","sev","level","priority"]) ||
          pick(f?.extra, ["severity","sev","level","priority"])
        ) || "INFO";
      };

      const pickTitle = (f)=>{
        return norm(
          pick(f, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id","query_name"]) ||
          pick(f?.meta, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id"]) ||
          pick(f?.extra, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id"])
        ) || "(no title)";
      };

      const pickLocation = (f)=>{
        // try common file fields
        const file = norm(
          pick(f, ["path","file","filename","file_path","filepath","uri"]) ||
          pick(f?.location, ["path","file","filename","file_path","filepath","uri"]) ||
          pick(f?.meta, ["path","file","filename","file_path","filepath","uri"]) ||
          pick(f?.extra, ["path","file","filename","file_path","filepath","uri"])
        );

        const line = pick(f, ["line","start_line","begin_line"]) || pick(f?.location, ["line","start_line","begin_line"]) || "";
        const col  = pick(f, ["col","column","start_col"]) || pick(f?.location, ["col","column","start_col"]) || "";

        const lc = (line || col) ? `:${line||""}${col?":"+col:""}` : "";
        return (file ? (file + lc) : (lc ? lc.slice(1) : "(no path)"));
      };

      async function getLatestRid(){
        const url = `/api/vsp/rid_latest_gate_root?_=${Date.now()}`;
        const r = await fetch(url, {cache:"no-store"});
        if (!r.ok) throw new Error(`rid_latest_gate_root http ${r.status}`);
        const j = await r.json();
        if (!j || !j.ok || !j.rid) throw new Error("rid_latest_gate_root invalid json");
        return j.rid;
      }

      async function fetchFindings(rid){
        const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_=${Date.now()}`;
        const r = await fetch(url, {cache:"no-store"});
        if (!r.ok) throw new Error(`findings_unified http ${r.status}`);
        const j = await r.json();
        const arr = Array.isArray(j) ? j : (Array.isArray(j?.findings) ? j.findings : []);
        return arr;
      }

      function scoreFinding(f){
        const sev = pickSeverity(f);
        const w = SEV_W[sev] || 150;
        // prefer items with a path/title
        const hasPath = pickLocation(f) && pickLocation(f) !== "(no path)" ? 20 : 0;
        const hasTitle = pickTitle(f) && pickTitle(f) !== "(no title)" ? 10 : 0;
        return w + hasPath + hasTitle;
      }

      function findButton(){
        const btns = Array.from(document.querySelectorAll("button, a"));
        for (const b of btns){
          const t = (b.textContent || "").trim();
          if (/^Load top findings\s*\(\s*25\s*\)\s*$/i.test(t)) return b;
        }
        return null;
      }

      function findTopFindingsTable(){
        // Find a heading-like leaf containing "Top findings"
        const leaves = Array.from(document.querySelectorAll("*"))
          .filter(el => el && el.children && el.children.length === 0);

        let anchor = null;
        for (const el of leaves){
          const tx = (el.textContent || "").trim();
          if (/^Top findings/i.test(tx)) { anchor = el; break; }
        }
        // fallback: any element with that substring
        if (!anchor){
          for (const el of leaves){
            const tx = (el.textContent || "").trim();
            if (/Top findings/i.test(tx)) { anchor = el; break; }
          }
        }
        if (!anchor) return null;

        // climb up to find a table inside
        let cur = anchor.parentElement;
        for (let i=0; i<12 && cur; i++){
          const t = cur.querySelector("table");
          if (t) return t;
          cur = cur.parentElement;
        }
        return null;
      }

      function renderRows(rows){
        const table = findTopFindingsTable();
        if (!table){
          console.warn("[VSP][DASH_ONLY] top findings table not found");
          return false;
        }
        let tbody = table.querySelector("tbody");
        if (!tbody){
          tbody = document.createElement("tbody");
          table.appendChild(tbody);
        }
        tbody.innerHTML = "";

        for (const r of rows){
          const tr = document.createElement("tr");
          tr.innerHTML = `
            <td>${r.sev}</td>
            <td>${r.tool}</td>
            <td title="${r.title.replaceAll('"','&quot;')}">${r.title}</td>
            <td title="${r.loc.replaceAll('"','&quot;')}">${r.loc}</td>
          `;
          tbody.appendChild(tr);
        }
        return true;
      }

      function renderMessage(msg){
        const table = findTopFindingsTable();
        if (!table) return;
        let tbody = table.querySelector("tbody");
        if (!tbody){
          tbody = document.createElement("tbody");
          table.appendChild(tbody);
        }
        tbody.innerHTML = `<tr><td colspan="4">${msg}</td></tr>`;
      }

      async function onClick(){
        const btn = findButton();
        if (!btn) return;

        btn.setAttribute("disabled","disabled");
        const old = btn.textContent;
        btn.textContent = "Loading…";

        try{
          const rid = await getLatestRid();
          if (cache[rid]){
            renderRows(cache[rid]);
            console.log("[VSP][DASH_ONLY] top findings from cache rid=", rid);
            return;
          }

          const arr = await fetchFindings(rid);
          if (!arr || arr.length === 0){
            renderMessage("No findings_unified.json (or empty).");
            console.warn("[VSP][DASH_ONLY] findings_unified empty rid=", rid);
            return;
          }

          const picked = arr
            .filter(x => x && typeof x === "object")
            .map(f => ({
              sev: pickSeverity(f),
              tool: pickTool(f),
              title: pickTitle(f),
              loc: pickLocation(f),
              _score: scoreFinding(f),
            }))
            .sort((a,b)=> (b._score - a._score) || (a.tool.localeCompare(b.tool)) || (a.title.localeCompare(b.title)))
            .slice(0, 25)
            .map(x => ({sev:x.sev, tool:x.tool, title:x.title, loc:x.loc}));

          cache[rid] = picked;
          renderRows(picked);
          console.log("[VSP][DASH_ONLY] loaded top findings rid=", rid, "n=", picked.length);
        }catch(e){
          console.warn("[VSP][DASH_ONLY] load top findings failed:", e);
          renderMessage("Load failed (see console).");
        }finally{
          // restore button
          btn.textContent = old || "Load top findings (25)";
          btn.removeAttribute("disabled");
        }
      }

      function bind(){
        const btn = findButton(); // may be null until UI renders
        if (!btn) return false;
        if (btn.__vsp_bound_topfind) return true;
        btn.__vsp_bound_topfind = true;
        btn.addEventListener("click", (ev)=> { ev.preventDefault(); onClick(); }, {passive:false});
        console.log("[VSP][DASH_ONLY] top-findings hook bound");
        return true;
      }

      // bind now + retry a few times (in case of late render)
      let tries = 0;
      const timer = setInterval(()=> {
        tries++;
        if (bind() || tries >= 12) clearInterval(timer);
      }, 500);

      setTimeout(bind, 1200);
      console.log("[VSP][DASH_ONLY] top-findings v1 active");
    })();
    """).strip("\n") + "\n"

    p.write_text(s + "\n\n" + patch, encoding="utf-8")
    print("[OK] appended:", MARK)

PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R), then click: Load top findings (25)."
