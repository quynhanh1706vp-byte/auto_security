#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p466a2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$F" "$OUT/$(basename "$F").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$F").bak_${TS}" | tee -a "$OUT/log.txt"

python3 - "$F" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P466A2_RUNS_DEDUPE_SORT_FIXLOADED_V1"
if MARK in s:
    print("[OK] already patched P466a2")
    raise SystemExit(0)

addon = r'''
/* --- VSP_P466A2_RUNS_DEDUPE_SORT_FIXLOADED_V1 --- */
(function(){
  if (window.__VSP_P466A2_ON) return;
  window.__VSP_P466A2_ON = true;

  const LS_SORT = "vsp_runs_sort_v1";
  const LS_SEL  = "vsp_runs_selected_rid_v1";

  function qs(sel, root){ return (root||document).querySelector(sel); }
  function qsa(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function txt(el){ return (el && el.textContent ? el.textContent : "").trim(); }

  function ensureCss(){
    if (qs("#vsp_p466a2_css")) return;
    const st=document.createElement("style");
    st.id="vsp_p466a2_css";
    st.textContent = `
      .vsp-p466a2-sort{ margin-left:10px; padding:8px 10px; border-radius:10px;
        border:1px solid rgba(255,255,255,.12); background: rgba(0,0,0,.25); color:#fff; }
      .vsp-p466a2-selected{ outline:2px solid rgba(255,255,255,.14); background: rgba(255,255,255,.04)!important; }
      .vsp-p466a2-hidden{ display:none!important; }
    `;
    document.head.appendChild(st);
  }

  function getSort(){
    try{ return (localStorage.getItem(LS_SORT)||"new"); }catch(e){ return "new"; }
  }
  function setSort(v){
    try{ localStorage.setItem(LS_SORT, v); }catch(e){}
  }
  function getSel(){
    try{ return (localStorage.getItem(LS_SEL)||"").trim(); }catch(e){ return ""; }
  }
  function setSel(rid){
    try{ localStorage.setItem(LS_SEL, String(rid||"").trim()); }catch(e){}
  }

  function findFilterInput(){
    return qs('input[placeholder*="Filter by RID"]')
        || qs('input[placeholder*="Filter by RID / label"]')
        || qs('input[placeholder*="Filter"]');
  }

  function findRunsRootFromInput(inp){
    return (inp && (inp.closest("section") || inp.closest(".card") || inp.closest("div"))) || document.body;
  }

  function ridFromRow(row){
    if (!row) return "";
    const d = (row.getAttribute("data-vsp-rid") || row.getAttribute("data-rid") || "").trim();
    if (d) return d;
    // first cell often RID
    const td = row.querySelector("td");
    const t = txt(td);
    if (t) return t;
    return "";
  }

  function tsFromRow(row){
    const t = txt(row);
    // match YYYY-MM-DD HH:MM (from your screenshot)
    const m = t.match(/(20\d{2})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})/);
    if (!m) return 0;
    const y=+m[1], mo=+m[2], d=+m[3], hh=+m[4], mm=+m[5];
    const dt = new Date(y, mo-1, d, hh, mm, 0, 0);
    return dt.getTime() || 0;
  }

  function isRunsRow(row){
    // In your UI, row has "Use RID" button + "Reports.tgz"
    const t = txt(row).toLowerCase();
    return t.includes("use rid") && (t.includes("reports.tgz") || t.includes("csv") || t.includes("dashboard"));
  }

  function getRunsRows(root){
    // Prefer table rows if exist
    const rows = qsa("tr", root).filter(isRunsRow);
    return rows;
  }

  function ensureSortSelect(inp){
    ensureCss();
    if (!inp) return null;
    if (inp.parentElement && qs("select.vsp-p466a2-sort", inp.parentElement)) return qs("select.vsp-p466a2-sort", inp.parentElement);

    const sel=document.createElement("select");
    sel.className="vsp-p466a2-sort";
    sel.innerHTML = `
      <option value="new">Sort: Newest</option>
      <option value="old">Sort: Oldest</option>
      <option value="none">Sort: None</option>
    `;
    sel.value = getSort();
    sel.addEventListener("change", ()=>{ setSort(sel.value); applyAll(); });

    // put right after input
    inp.insertAdjacentElement("afterend", sel);
    return sel;
  }

  function patchRunsLoaded(uniqueCount){
    // Replace any "Runs loaded: undefined" text we can find
    const nodes = qsa("*").slice(0, 2500); // keep safe
    for (const el of nodes){
      const t = el.childElementCount === 0 ? txt(el) : "";
      if (t && t.includes("Runs loaded:") && t.includes("undefined")){
        el.textContent = "Runs loaded: " + String(uniqueCount);
      }
    }
  }

  function highlightSelected(rows){
    const sel = getSel();
    for(const r of rows){
      const rid = ridFromRow(r);
      if (rid && sel && rid === sel) r.classList.add("vsp-p466a2-selected");
      else r.classList.remove("vsp-p466a2-selected");
    }
  }

  function dedupeRows(rows){
    const seen = new Set();
    let unique = 0;
    for (const r of rows){
      const rid = ridFromRow(r);
      const ts  = tsFromRow(r);
      const key = (rid||"") + "|" + String(ts||0);
      if (!rid) { r.classList.remove("vsp-p466a2-hidden"); continue; }
      if (seen.has(key)){
        r.classList.add("vsp-p466a2-hidden");
      }else{
        seen.add(key);
        r.classList.remove("vsp-p466a2-hidden");
        unique += 1;
      }
    }
    return unique;
  }

  function sortRows(rows, mode){
    if (mode === "none") return;
    const visible = rows.filter(r=>!r.classList.contains("vsp-p466a2-hidden"));
    visible.sort((a,b)=>{
      const ta = tsFromRow(a), tb = tsFromRow(b);
      if (ta === tb){
        const ra = ridFromRow(a), rb = ridFromRow(b);
        return ra < rb ? -1 : ra > rb ? 1 : 0;
      }
      return mode === "new" ? (tb - ta) : (ta - tb);
    });
    // append back in order (keeps them inside same tbody/container)
    const parent = visible[0] ? visible[0].parentElement : null;
    if (!parent) return;
    for (const r of visible) parent.appendChild(r);
  }

  function bindSelectByClick(root){
    // store selection when user hits "Use RID" button
    root.addEventListener("click", (ev)=>{
      const btn = ev.target && ev.target.closest ? ev.target.closest("button, a") : null;
      if (!btn) return;
      const btxt = txt(btn).toLowerCase();
      if (!btxt.includes("use rid")) return;
      const row = btn.closest("tr");
      const rid = ridFromRow(row);
      if (rid) setSel(rid);
      // re-apply highlight
      const rows = getRunsRows(root);
      highlightSelected(rows);
    }, true);
  }

  function applyAll(){
    const inp = findFilterInput();
    if (!inp) return;
    const root = findRunsRootFromInput(inp);

    ensureSortSelect(inp);
    bindSelectByClick(root);

    const rows = getRunsRows(root);
    if (!rows.length) return;

    const unique = dedupeRows(rows);
    sortRows(rows, getSort());
    highlightSelected(rows);
    patchRunsLoaded(unique);
  }

  // run periodically (safe, idempotent)
  setInterval(applyAll, 900);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ()=>setTimeout(applyAll, 150));
  else setTimeout(applyAll, 150);
})();
/* --- /VSP_P466A2_RUNS_DEDUPE_SORT_FIXLOADED_V1 --- */
'''
p.write_text(s.rstrip()+"\n\n"+addon+"\n", encoding="utf-8")
print("[OK] appended P466a2 addon")
PY

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" || true
fi

echo "[OK] P466a2 done. Hard refresh /c/runs. You should see a Sort dropdown next to filter + duplicates hidden + loaded count fixed." | tee -a "$OUT/log.txt"
