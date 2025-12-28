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
cp -f "$JS" "${JS}.bak_topfind_v2_${TS}"
echo "[BACKUP] ${JS}.bak_topfind_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

def strip_block(mark: str, s: str) -> str:
    # remove block from /* MARK ... until next /* VSP_P0_... or EOF
    return re.sub(rf"/\*\s*{re.escape(mark)}[\s\S]*?(?=/\*\s*VSP_P0_|$)", "", s, flags=re.M)

s2 = s
s2 = strip_block("VSP_P0_DASH_ONLY_LOAD_TOP_FINDINGS_V1", s2)
s2 = strip_block("VSP_P0_DASH_ONLY_LOAD_TOP_FINDINGS_V2", s2)

patch = textwrap.dedent(r"""
/* VSP_P0_DASH_ONLY_LOAD_TOP_FINDINGS_V2
   Replace v1 with robust render into the "Not loaded" area (no fragile table selector).
   Debug logs: click -> rid -> fetch -> render.
*/
(()=> {
  if (window.__vsp_p0_dash_only_load_top_findings_v2) return;
  window.__vsp_p0_dash_only_load_top_findings_v2 = true;

  const cache = window.__vsp_dash_only_cache_findings || (window.__vsp_dash_only_cache_findings = {});
  const SEV_W = {CRITICAL:600,HIGH:500,MEDIUM:400,LOW:300,INFO:200,TRACE:100};

  const norm = (v)=> (v==null ? "" : String(v)).trim();
  const normSev = (v)=>{
    const x = norm(v).toUpperCase();
    if (!x) return "INFO";
    if (x === "CRIT") return "CRITICAL";
    if (x === "WARN" || x === "WARNING") return "MEDIUM";
    return x;
  };

  const pick = (obj, keys)=>{
    if (!obj || typeof obj !== "object") return "";
    for (const k of keys) if (obj[k] != null) return obj[k];
    return "";
  };

  const pickTool = (f)=> norm(
    pick(f, ["tool","engine","scanner","source","detector","product","provider"]) ||
    pick(f?.meta, ["tool","engine","scanner","source"]) ||
    pick(f?.extra, ["tool","engine","scanner","source"])
  ) || "UNKNOWN";

  const pickSeverity = (f)=> normSev(
    pick(f, ["severity","sev","level","priority"]) ||
    pick(f?.meta, ["severity","sev","level","priority"]) ||
    pick(f?.extra, ["severity","sev","level","priority"])
  );

  const pickTitle = (f)=> norm(
    pick(f, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id","query_name"]) ||
    pick(f?.meta, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id"]) ||
    pick(f?.extra, ["title","message","name","summary","rule_name","rule","check_name","id","rule_id"])
  ) || "(no title)";

  const pickLocation = (f)=>{
    const file = norm(
      pick(f, ["path","file","filename","file_path","filepath","uri"]) ||
      pick(f?.location, ["path","file","filename","file_path","filepath","uri"]) ||
      pick(f?.meta, ["path","file","filename","file_path","filepath","uri"]) ||
      pick(f?.extra, ["path","file","filename","file_path","filepath","uri"])
    );
    const line = pick(f, ["line","start_line","begin_line"]) || pick(f?.location, ["line","start_line","begin_line"]) || "";
    const col  = pick(f, ["col","column","start_col"]) || pick(f?.location, ["col","column","start_col"]) || "";
    const lc = (line || col) ? `:${line||""}${col?":"+col:""}` : "";
    return (file ? (file + lc) : "(no path)");
  };

  function scoreFinding(f){
    const sev = pickSeverity(f);
    const w = SEV_W[sev] || 150;
    const hasPath = pickLocation(f) !== "(no path)" ? 20 : 0;
    const hasTitle = pickTitle(f) !== "(no title)" ? 10 : 0;
    return w + hasPath + hasTitle;
  }

  async function getLatestRid(){
    const url = `/api/vsp/rid_latest_gate_root?_=${Date.now()}`;
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`rid_latest http ${r.status}`);
    const j = await r.json();
    if (!j?.ok || !j?.rid) throw new Error("rid_latest invalid json");
    return j.rid;
  }

  async function fetchFindings(rid){
    const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=findings_unified.json&_=${Date.now()}`;
    const r = await fetch(url, {cache:"no-store"});
    if (!r.ok) throw new Error(`findings http ${r.status}`);
    const j = await r.json();
    const arr = Array.isArray(j) ? j : (Array.isArray(j?.findings) ? j.findings : []);
    return arr;
  }

  function findButton(){
    const btns = Array.from(document.querySelectorAll("button, a"));
    for (const b of btns){
      const t = (b.textContent || "").trim();
      if (/^Load top findings\s*\(\s*25\s*\)\s*$/i.test(t)) return b;
    }
    return null;
  }

  function findTopFindingsSectionRoot(){
    // Find "Top findings" label, then climb to a container that contains the column headers
    const all = Array.from(document.querySelectorAll("*"));
    const leaf = all.find(el => (el.textContent||"").trim().toLowerCase().startsWith("top findings"));
    if (!leaf) return null;

    let cur = leaf;
    for (let i=0; i<14 && cur; i++){
      const txt = (cur.textContent||"").toLowerCase();
      if (txt.includes("severity") && txt.includes("tool") && txt.includes("title") && txt.includes("location")){
        return cur;
      }
      cur = cur.parentElement;
    }
    return leaf.parentElement;
  }

  function renderMessage(msg){
    const root = findTopFindingsSectionRoot();
    if (!root) { console.warn("[VSP][DASH_ONLY] topfind root not found"); return; }

    // Prefer replacing the "Not loaded" cell if present
    const nl = Array.from(root.querySelectorAll("*")).find(el => (el.textContent||"").trim().toLowerCase() === "not loaded");
    if (nl){
      nl.textContent = msg;
      return;
    }

    // fallback: append a small message block
    let box = root.querySelector("[data-vsp-topfind-msg]");
    if (!box){
      box = document.createElement("div");
      box.setAttribute("data-vsp-topfind-msg","1");
      box.style.marginTop = "8px";
      root.appendChild(box);
    }
    box.textContent = msg;
  }

  function renderRows(rows){
    const root = findTopFindingsSectionRoot();
    if (!root) { console.warn("[VSP][DASH_ONLY] topfind root not found"); return false; }

    // If there's a table, use it; otherwise replace "Not loaded" area with a mini table.
    const table = root.querySelector("table");
    if (table){
      let tbody = table.querySelector("tbody");
      if (!tbody){
        tbody = document.createElement("tbody");
        table.appendChild(tbody);
      }
      tbody.innerHTML = "";
      for (const r of rows){
        const tr = document.createElement("tr");
        tr.innerHTML = `<td>${r.sev}</td><td>${r.tool}</td><td>${r.title}</td><td>${r.loc}</td>`;
        tbody.appendChild(tr);
      }
      return true;
    }

    // No table: replace "Not loaded" node's parent with table markup
    const nl = Array.from(root.querySelectorAll("*")).find(el => (el.textContent||"").trim().toLowerCase() === "not loaded");
    const host = nl ? (nl.closest("div") || nl.parentElement || root) : root;

    const html = [
      `<table style="width:100%;border-collapse:collapse;margin-top:6px">`,
      `<tbody>`,
      ...rows.map(r => `<tr><td>${r.sev}</td><td>${r.tool}</td><td>${r.title}</td><td>${r.loc}</td></tr>`),
      `</tbody></table>`
    ].join("");

    host.innerHTML = html;
    return true;
  }

  async function onClick(){
    console.log("[VSP][DASH_ONLY] topfind click");
    const btn = findButton();
    if (!btn) { console.warn("[VSP][DASH_ONLY] topfind button missing"); return; }

    btn.setAttribute("disabled","disabled");
    const old = btn.textContent;
    btn.textContent = "Loading…";

    try{
      const rid = await getLatestRid();
      console.log("[VSP][DASH_ONLY] topfind rid=", rid);

      if (cache[rid]){
        renderRows(cache[rid]);
        console.log("[VSP][DASH_ONLY] topfind from cache n=", cache[rid].length);
        return;
      }

      const arr = await fetchFindings(rid);
      console.log("[VSP][DASH_ONLY] topfind raw findings n=", arr?.length || 0);

      if (!arr || arr.length === 0){
        renderMessage("No findings_unified.json (or empty).");
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
        .sort((a,b)=> (b._score - a._score))
        .slice(0, 25)
        .map(x => ({sev:x.sev, tool:x.tool, title:x.title, loc:x.loc}));

      cache[rid] = picked;
      const ok = renderRows(picked);
      console.log("[VSP][DASH_ONLY] topfind render ok=", ok, "n=", picked.length);
      if (!ok) renderMessage("Render target not found (see console).");
    }catch(e){
      console.warn("[VSP][DASH_ONLY] topfind failed:", e);
      renderMessage("Load failed (see console).");
    }finally{
      btn.textContent = old || "Load top findings (25)";
      btn.removeAttribute("disabled");
    }
  }

  function bind(){
    const btn = findButton();
    if (!btn) return false;
    if (btn.__vsp_bound_topfind_v2) return true;
    btn.__vsp_bound_topfind_v2 = true;
    btn.addEventListener("click", (ev)=>{ ev.preventDefault(); onClick(); }, {passive:false});
    console.log("[VSP][DASH_ONLY] topfind v2 hook bound");
    return true;
  }

  let tries = 0;
  const t = setInterval(()=>{ tries++; if (bind() || tries>=14) clearInterval(t); }, 500);
  setTimeout(bind, 1200);

  console.log("[VSP][DASH_ONLY] topfind v2 active");
})();
""").strip("\n") + "\n"

p.write_text(s2.strip() + "\n\n" + patch, encoding="utf-8")
print("[OK] replaced topfind block with V2")
PY

echo "== restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R) then CLICK: Load top findings (25)."
