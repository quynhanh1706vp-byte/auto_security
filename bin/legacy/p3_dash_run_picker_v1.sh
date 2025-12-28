#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_luxe_v1.js"
MARK="VSP_P3_RUN_PICKER_V1"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runpicker_${TS}"
echo "[BACKUP] ${JS}.bak_runpicker_${TS}"

# IMPORTANT: use <<'PY' to prevent bash expanding backticks/template literals inside the block
python3 - "$JS" "$MARK" <<'PY'
from pathlib import Path
import sys, textwrap

js_path = sys.argv[1]
mark = sys.argv[2]

p = Path(js_path)
s = p.read_text(encoding="utf-8", errors="ignore")

if mark in s:
    print("[OK] already patched:", mark)
    sys.exit(0)

block = textwrap.dedent(r"""
/* ===================== VSP_P3_RUN_PICKER_V1 ===================== */
(function(){
  try{
    if (window.__VSP_RUN_PICKER_V1__) return;
    window.__VSP_RUN_PICKER_V1__ = true;

    function qp(name){
      try { return new URL(location.href).searchParams.get(name) || ""; }
      catch(e){ return ""; }
    }
    function lsGet(k){
      try { return localStorage.getItem(k) || ""; } catch(e){ return ""; }
    }
    function lsSet(k,v){
      try { localStorage.setItem(k, v); } catch(e){}
    }
    async function fetchJson(url){
      const r = await fetch(url, { credentials: "same-origin" });
      if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
      return await r.json();
    }
    function applyRid(rid){
      if(!rid) return;
      lsSet("vsp_rid_selected", rid);
      const u = new URL(location.href);
      u.searchParams.set("rid", rid);
      location.href = u.toString(); // safest P0: full reload
    }

    function cssInline(){
      return [
        "display:flex",
        "align-items:center",
        "gap:10px",
        "padding:10px 12px",
        "margin:10px 0 14px 0",
        "border:1px solid rgba(255,255,255,0.10)",
        "border-radius:12px",
        "background:rgba(20,22,28,0.75)",
        "backdrop-filter:blur(6px)",
        "color:#eaeaea"
      ].join(";");
    }
    function selectCss(){
      return [
        "min-width:420px",
        "max-width:72vw",
        "padding:8px 10px",
        "border-radius:10px",
        "border:1px solid rgba(255,255,255,0.14)",
        "background:rgba(10,12,16,0.85)",
        "color:#eaeaea",
        "outline:none"
      ].join(";");
    }
    function smallCss(){
      return "opacity:0.8;font-size:12px";
    }

    function mount(){
      const main = document.getElementById("vsp-dashboard-main");
      if(!main) return false;

      const host = main.parentElement || document.body;
      if(document.getElementById("vsp-run-picker-bar")) return true;

      const bar = document.createElement("div");
      bar.id = "vsp-run-picker-bar";
      bar.setAttribute("data-marker", "VSP_P3_RUN_PICKER_V1");
      bar.style.cssText = cssInline();
      bar.innerHTML = `
        <div style="font-weight:700;">Run</div>
        <select id="vsp-run-picker-select" style="${selectCss()}">
          <option value="" disabled selected>Loading runs…</option>
        </select>
        <div id="vsp-run-picker-hint" style="${smallCss()}"></div>
      `;
      host.insertBefore(bar, host.firstChild);
      return true;
    }

    function normalizeRuns(j){
      const runs = (j && (j.runs || j.items || j.data)) || [];
      const out = [];
      for(const r of runs){
        const rid = (r && (r.rid || r.run_id || r.id || r.RID)) || "";
        if(rid) out.push({ rid, raw: r });
      }
      return out;
    }

    async function fillOptions(){
      const sel = document.getElementById("vsp-run-picker-select");
      const hint = document.getElementById("vsp-run-picker-hint");
      if(!sel) return;

      const currentRid = qp("rid") || lsGet("vsp_rid_selected");

      sel.innerHTML = "";

      const optLatest = document.createElement("option");
      optLatest.value = "__LATEST__";
      optLatest.textContent = "Latest with findings";
      sel.appendChild(optLatest);

      const optSep = document.createElement("option");
      optSep.value = "__SEP__";
      optSep.textContent = "──────── Recent runs ────────";
      optSep.disabled = true;
      sel.appendChild(optSep);

      let runs = [];
      try{
        const j = await fetchJson("/api/vsp/runs?limit=30&offset=0");
        runs = normalizeRuns(j);
      }catch(e){
        if(hint) hint.textContent = "Failed to load runs: " + (e && e.message ? e.message : e);
      }

      for(const it of runs){
        const o = document.createElement("option");
        o.value = it.rid;
        o.textContent = it.rid;
        sel.appendChild(o);
      }

      if(currentRid){
        const exists = Array.from(sel.options).some(o => o.value === currentRid);
        if(!exists){
          const o = document.createElement("option");
          o.value = currentRid;
          o.textContent = currentRid + " (current)";
          sel.insertBefore(o, optSep.nextSibling);
        }
        sel.value = currentRid;
        if(hint) hint.textContent = "Current RID: " + currentRid;
      }else{
        sel.value = "__LATEST__";
        if(hint) hint.textContent = "Tip: pick a run to refresh KPI/Charts instantly.";
      }

      sel.addEventListener("change", async () => {
        const v = sel.value;
        if(v === "__LATEST__"){
          try{
            const j = await fetchJson("/api/vsp/rid_latest");
            const rid = (j && j.rid) || "";
            if(rid) applyRid(rid);
          }catch(e){
            if(hint) hint.textContent = "Failed to resolve latest rid: " + (e && e.message ? e.message : e);
          }
          return;
        }
        if(v && v !== "__SEP__") applyRid(v);
      }, { once: true });
    }

    async function boot(){
      if(document.readyState === "loading"){
        document.addEventListener("DOMContentLoaded", boot, { once:true });
        return;
      }
      if(!mount()) return;
      await fillOptions();
    }

    boot();
  }catch(e){
    try{ console.warn("[RunPickerV1] init error:", e); }catch(_){}
  }
})();
 /* ===================== /VSP_P3_RUN_PICKER_V1 ===================== */
""").strip("\n") + "\n"

p.write_text(s.rstrip("\n") + "\n\n" + block, encoding="utf-8")
print("[OK] patched:", mark, "=>", str(p))
PY

echo "== [restart] =="
systemctl restart "$SVC" 2>/dev/null || true

echo "== [verify] /vsp5 contains JS + marker =="
curl -fsS "$BASE/vsp5" | grep -q "vsp_dashboard_luxe_v1.js" && echo "[OK] vsp5 loads vsp_dashboard_luxe_v1.js" || { echo "[ERR] vsp5 missing luxe js"; exit 2; }
curl -fsS "$BASE/static/js/vsp_dashboard_luxe_v1.js" | grep -q "$MARK" && echo "[OK] marker present in JS" || { echo "[ERR] marker missing in JS"; exit 2; }

echo "== [verify] runs + rid_latest endpoints =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 160; echo
curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | head -c 220; echo

echo "[DONE] Run picker installed. Open: $BASE/vsp5"
