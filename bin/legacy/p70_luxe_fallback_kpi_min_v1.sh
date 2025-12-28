#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p70_${TS}"
echo "[OK] backup ${F}.bak_p70_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P70_FALLBACK_KPI_MIN_V1" in s:
    print("[OK] already patched P70")
    raise SystemExit(0)

inject = r"""
/* VSP_P70_FALLBACK_KPI_MIN_V1
 * Goal: If dashboard is still blank, render a minimal KPI + Top Findings view using datasource + top_findings_v2.
 */
(function(){
  try{
    function nativeGE(id){ try { return Document.prototype.getElementById.call(document, id); } catch(e){ return null; } }
    function hostEl(){
      // Prefer SAFE getter from P69B if exists
      try{
        if (window.__VSP_GET_SAFE) {
          return window.__VSP_GET_SAFE("vsp-dashboard-main") || window.__VSP_GET_SAFE("vsp5_root") || document.body;
        }
      }catch(e){}
      return nativeGE("vsp-dashboard-main") || nativeGE("vsp5_root") || document.body;
    }

    function getRID(){
      try{
        const u = new URL(window.location.href);
        return u.searchParams.get("rid") || "";
      }catch(e){
        const m = (window.location.search||"").match(/[?&]rid=([^&]+)/);
        return m ? decodeURIComponent(m[1]) : "";
      }
    }

    async function fetchJSON(url){
      const r = await fetch(url, {credentials:"same-origin"});
      const ct = (r.headers.get("content-type")||"");
      if (!r.ok) throw new Error("HTTP "+r.status+" for "+url);
      if (ct.includes("application/json")) return await r.json();
      // best-effort
      const t = await r.text();
      try { return JSON.parse(t); } catch(e){ return {"ok":false,"raw":t}; }
    }

    function pickSevCounts(ds){
      // Try common shapes
      const k = ds && ds.kpis ? ds.kpis : null;
      if (k && typeof k === "object") {
        // direct map?
        const cand = k.by_sev || k.severity || k.sev || k.counts || k;
        if (cand && typeof cand === "object") {
          const out = {};
          ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"].forEach(sv=>{
            let v = cand[sv];
            if (v == null) v = cand[sv.toLowerCase()];
            if (v == null) v = cand[sv.toLowerCase().slice(0,4)];
            if (typeof v === "number") out[sv]=v;
          });
          if (Object.keys(out).length) return out;
        }
      }
      // Compute from findings list if possible
      const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      const arr = (ds && ds.findings) ? ds.findings : [];
      if (Array.isArray(arr)) {
        for (const f of arr) {
          const sv = String((f && (f.severity || f.sev || f.level)) || "").toUpperCase();
          if (out[sv] != null) out[sv] += 1;
        }
        return out;
      }
      return out;
    }

    function mk(tag, attrs, text){
      const el = document.createElement(tag);
      if (attrs) for (const k in attrs) el.setAttribute(k, attrs[k]);
      if (text != null) el.textContent = text;
      return el;
    }

    function render(ds, top){
      const host = hostEl();
      const dash = nativeGE("vsp-dashboard-main") || host;

      // If already rendered something meaningful, don't override
      const meaningful = (dash.children && dash.children.length > 0 && !dash.querySelector("[data-vsp-p70-root]"));
      if (meaningful) return;

      // Clear only our own previous fallback
      const old = dash.querySelector("[data-vsp-p70-root]");
      if (old) old.remove();

      const root = mk("div", {"data-vsp-p70-root":"1"});
      root.style.padding = "14px 16px";
      root.style.margin = "10px 0";

      const h1 = mk("div", null, "Dashboard (Fallback KPIs)");
      h1.style.fontSize = "14px";
      h1.style.fontWeight = "700";
      h1.style.color = "rgba(255,255,255,.88)";
      h1.style.marginBottom = "10px";
      root.appendChild(h1);

      const grid = mk("div");
      grid.style.display = "grid";
      grid.style.gridTemplateColumns = "repeat(6, minmax(0, 1fr))";
      grid.style.gap = "10px";

      function card(title, value){
        const c = mk("div");
        c.style.border = "1px solid rgba(255,255,255,.10)";
        c.style.borderRadius = "12px";
        c.style.background = "rgba(255,255,255,.04)";
        c.style.padding = "10px 10px";
        const t = mk("div", null, title);
        t.style.fontSize = "11px";
        t.style.color = "rgba(255,255,255,.62)";
        const v = mk("div", null, String(value));
        v.style.fontSize = "18px";
        v.style.fontWeight = "800";
        v.style.color = "rgba(255,255,255,.92)";
        v.style.marginTop = "6px";
        c.appendChild(t); c.appendChild(v);
        return c;
      }

      const total = (ds && (ds.total ?? ds.returned ?? (Array.isArray(ds.findings)?ds.findings.length:null))) ?? "-";
      grid.appendChild(card("TOTAL", total));

      const sev = pickSevCounts(ds);
      grid.appendChild(card("CRITICAL", sev.CRITICAL ?? 0));
      grid.appendChild(card("HIGH", sev.HIGH ?? 0));
      grid.appendChild(card("MEDIUM", sev.MEDIUM ?? 0));
      grid.appendChild(card("LOW", sev.LOW ?? 0));
      grid.appendChild(card("INFO", sev.INFO ?? 0));

      root.appendChild(grid);

      // Top findings list
      const box = mk("div");
      box.style.marginTop = "12px";
      box.style.border = "1px solid rgba(255,255,255,.10)";
      box.style.borderRadius = "12px";
      box.style.background = "rgba(0,0,0,.18)";
      box.style.padding = "10px 12px";

      const h2 = mk("div", null, "Top Findings (v2)");
      h2.style.fontSize = "12px";
      h2.style.fontWeight = "700";
      h2.style.color = "rgba(255,255,255,.80)";
      h2.style.marginBottom = "8px";
      box.appendChild(h2);

      const items = (top && top.items && Array.isArray(top.items)) ? top.items : [];
      if (!items.length) {
        const em = mk("div", null, "(no items)");
        em.style.color = "rgba(255,255,255,.55)";
        em.style.fontSize = "11px";
        box.appendChild(em);
      } else {
        const ul = mk("div");
        ul.style.display = "grid";
        ul.style.gap = "6px";
        for (const it of items.slice(0, 8)) {
          const row = mk("div");
          row.style.display = "flex";
          row.style.justifyContent = "space-between";
          row.style.gap = "10px";
          row.style.border = "1px solid rgba(255,255,255,.06)";
          row.style.borderRadius = "10px";
          row.style.padding = "8px 10px";
          row.style.background = "rgba(255,255,255,.03)";

          const left = mk("div");
          left.style.minWidth = "0";
          const title = (it.title || it.rule_id || it.id || it.cwe || it.category || "finding").toString();
          const sev = (it.severity || it.sev || it.level || "").toString().toUpperCase();
          const a = mk("div", null, title);
          a.style.color = "rgba(255,255,255,.85)";
          a.style.fontSize = "12px";
          a.style.whiteSpace = "nowrap";
          a.style.overflow = "hidden";
          a.style.textOverflow = "ellipsis";
          const b = mk("div", null, (it.tool ? ("tool="+it.tool+"  ") : "") + (it.where ? ("where="+it.where) : ""));
          b.style.color = "rgba(255,255,255,.50)";
          b.style.fontSize = "10px";
          b.style.marginTop = "2px";
          left.appendChild(a); left.appendChild(b);

          const right = mk("div", null, sev || "-");
          right.style.color = "rgba(255,255,255,.78)";
          right.style.fontSize = "11px";
          right.style.fontWeight = "700";
          right.style.flex = "0 0 auto";

          row.appendChild(left); row.appendChild(right);
          ul.appendChild(row);
        }
        box.appendChild(ul);
      }

      root.appendChild(box);

      // footer info
      const meta = mk("div", null, "rid=" + (ds.rid || getRID() || "-") + "  run_id=" + (ds.run_id || "-"));
      meta.style.marginTop = "10px";
      meta.style.fontSize = "10px";
      meta.style.color = "rgba(255,255,255,.45)";
      root.appendChild(meta);

      // ensure dash has content
      dash.appendChild(root);
    }

    async function run(){
      const rid = getRID();
      if (!rid) { console.warn("[VSP] P70 no rid in URL"); return; }
      console.info("[VSP] P70 fallback check rid=", rid);

      const dash = nativeGE("vsp-dashboard-main");
      // If dashboard already has children, do nothing
      if (dash && dash.children && dash.children.length > 0) return;

      try{
        const [ds, top] = await Promise.all([
          fetchJSON("/api/vsp/datasource?rid="+encodeURIComponent(rid)),
          fetchJSON("/api/vsp/top_findings_v2?limit=8")
        ]);
        render(ds, top);
        console.info("[VSP] P70 rendered fallback KPIs");
      }catch(e){
        console.warn("[VSP] P70 fallback fetch/render failed:", e);
        // still show a minimal banner so it won't look dead
        try{
          const host = nativeGE("vsp-dashboard-main") || hostEl();
          const note = mk("div", {"data-vsp-p70-root":"1"}, "[VSP] Fallback failed: "+String(e));
          note.style.padding="12px 14px";
          note.style.margin="10px 0";
          note.style.border="1px solid rgba(255,255,255,.10)";
          note.style.borderRadius="12px";
          note.style.background="rgba(255,255,255,.04)";
          note.style.color="rgba(255,255,255,.70)";
          host.appendChild(note);
        }catch(_){}
      }
    }

    // Run fallback only if still blank after a short delay
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function(){ setTimeout(run, 900); }, {once:true});
    } else {
      setTimeout(run, 900);
    }
  }catch(e){}
})();
"""

if '"use strict"' in s:
    s = re.sub(r'("use strict"\s*;)', r'\1\n'+inject, s, count=1)
else:
    s = inject + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] P70 injected fallback KPI renderer")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P70 applied. Hard refresh: Ctrl+Shift+R"
