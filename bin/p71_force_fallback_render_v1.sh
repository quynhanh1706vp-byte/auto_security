#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p71_${TS}"
echo "[OK] backup ${F}.bak_p71_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P71_FORCE_FALLBACK_RENDER_V1" in s:
    print("[OK] already patched P71")
    raise SystemExit(0)

inject = r"""
/* VSP_P71_FORCE_FALLBACK_RENDER_V1
 * Purpose: Always render a visible fallback panel into the real page (even if vsp5_root is empty).
 */
(function(){
  try{
    function nativeGE(id){ try { return Document.prototype.getElementById.call(document, id); } catch(e){ return null; } }
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
      if (!r.ok) throw new Error("HTTP "+r.status+" "+url);
      return await r.json();
    }

    function ensureHost(){
      // Prefer existing #vsp-dashboard-main if present
      let host = nativeGE("vsp-dashboard-main");
      if (host) return host;

      // Try common containers
      host = document.querySelector("main") ||
             document.querySelector("#content") ||
             document.querySelector(".content") ||
             document.querySelector("body");
      if (!host) host = document.body;

      // Create #vsp-dashboard-main right after the header area if possible
      const hdr = document.querySelector("header") || document.querySelector(".topbar") || null;

      const box = document.createElement("div");
      box.id = "vsp-dashboard-main";
      box.style.padding = "14px 16px";
      box.style.margin = "10px 12px";
      box.style.border = "1px solid rgba(255,255,255,.10)";
      box.style.borderRadius = "14px";
      box.style.background = "rgba(255,255,255,.03)";
      box.style.backdropFilter = "blur(2px)";
      box.style.color = "rgba(255,255,255,.86)";

      if (hdr && hdr.parentNode) {
        hdr.parentNode.insertBefore(box, hdr.nextSibling);
      } else if (host === document.body) {
        document.body.insertBefore(box, document.body.firstChild);
      } else {
        host.insertBefore(box, host.firstChild);
      }
      return box;
    }

    function mk(tag, txt){
      const el = document.createElement(tag);
      if (txt != null) el.textContent = txt;
      return el;
    }

    function sevCounts(ds){
      const out = {CRITICAL:0,HIGH:0,MEDIUM:0,LOW:0,INFO:0,TRACE:0};
      const k = ds && ds.kpis ? ds.kpis : null;

      // try direct map
      const cand = k && (k.by_sev || k.severity || k.sev || k.counts || k);
      if (cand && typeof cand === "object") {
        for (const key of Object.keys(out)) {
          let v = cand[key];
          if (v == null) v = cand[key.toLowerCase()];
          if (typeof v === "number") out[key] = v;
        }
        return out;
      }

      // compute from findings list
      const arr = (ds && Array.isArray(ds.findings)) ? ds.findings : [];
      for (const f of arr) {
        const sv = String((f && (f.severity || f.sev || f.level)) || "").toUpperCase();
        if (out[sv] != null) out[sv] += 1;
      }
      return out;
    }

    function render(ds, top){
      const host = ensureHost();

      // Remove previous P71 panel
      const old = host.querySelector("[data-vsp-p71]");
      if (old) old.remove();

      const root = document.createElement("div");
      root.setAttribute("data-vsp-p71","1");

      const title = mk("div","Dashboard (FORCED Fallback)");
      title.style.fontWeight="800";
      title.style.fontSize="13px";
      title.style.marginBottom="10px";
      root.appendChild(title);

      const grid = document.createElement("div");
      grid.style.display="grid";
      grid.style.gridTemplateColumns="repeat(6, minmax(0, 1fr))";
      grid.style.gap="10px";

      function card(name, val){
        const c=document.createElement("div");
        c.style.border="1px solid rgba(255,255,255,.10)";
        c.style.borderRadius="12px";
        c.style.background="rgba(0,0,0,.18)";
        c.style.padding="10px 10px";
        const a=mk("div",name);
        a.style.fontSize="11px";
        a.style.color="rgba(255,255,255,.62)";
        const b=mk("div",String(val));
        b.style.fontSize="18px";
        b.style.fontWeight="900";
        b.style.marginTop="6px";
        c.appendChild(a); c.appendChild(b);
        return c;
      }

      const total = (ds && (ds.total ?? (Array.isArray(ds.findings)?ds.findings.length:null))) ?? "-";
      const sev = sevCounts(ds);

      grid.appendChild(card("TOTAL", total));
      grid.appendChild(card("CRITICAL", sev.CRITICAL));
      grid.appendChild(card("HIGH", sev.HIGH));
      grid.appendChild(card("MEDIUM", sev.MEDIUM));
      grid.appendChild(card("LOW", sev.LOW));
      grid.appendChild(card("INFO", sev.INFO));

      root.appendChild(grid);

      const box = document.createElement("div");
      box.style.marginTop="12px";
      box.style.border="1px solid rgba(255,255,255,.10)";
      box.style.borderRadius="12px";
      box.style.background="rgba(0,0,0,.16)";
      box.style.padding="10px 12px";

      const h2 = mk("div","Top Findings (v2)");
      h2.style.fontWeight="800";
      h2.style.fontSize="12px";
      h2.style.marginBottom="8px";
      box.appendChild(h2);

      const items = top && Array.isArray(top.items) ? top.items : [];
      if (!items.length) {
        const em = mk("div","(no items)");
        em.style.fontSize="11px";
        em.style.color="rgba(255,255,255,.60)";
        box.appendChild(em);
      } else {
        const list = document.createElement("div");
        list.style.display="grid";
        list.style.gap="6px";
        for (const it of items.slice(0,8)) {
          const row=document.createElement("div");
          row.style.display="flex";
          row.style.justifyContent="space-between";
          row.style.gap="10px";
          row.style.border="1px solid rgba(255,255,255,.06)";
          row.style.borderRadius="10px";
          row.style.padding="8px 10px";
          row.style.background="rgba(255,255,255,.03)";

          const left=document.createElement("div");
          left.style.minWidth="0";
          const t=(it.title||it.rule_id||it.id||it.cwe||it.category||"finding").toString();
          const sev=(it.severity||it.sev||it.level||"").toString().toUpperCase();
          const a=mk("div",t);
          a.style.whiteSpace="nowrap";
          a.style.overflow="hidden";
          a.style.textOverflow="ellipsis";
          a.style.fontSize="12px";
          const b=mk("div",(it.tool?("tool="+it.tool+"  "):"") + (it.where?("where="+it.where):""));
          b.style.fontSize="10px";
          b.style.color="rgba(255,255,255,.55)";
          b.style.marginTop="2px";
          left.appendChild(a); left.appendChild(b);

          const right=mk("div",sev||"-");
          right.style.fontSize="11px";
          right.style.fontWeight="800";
          right.style.flex="0 0 auto";
          right.style.opacity="0.9";

          row.appendChild(left); row.appendChild(right);
          list.appendChild(row);
        }
        box.appendChild(list);
      }

      root.appendChild(box);

      const meta = mk("div","rid="+(ds.rid||"-")+"  run_id="+(ds.run_id||"-"));
      meta.style.marginTop="10px";
      meta.style.fontSize="10px";
      meta.style.color="rgba(255,255,255,.45)";
      root.appendChild(meta);

      host.appendChild(root);
    }

    async function run(){
      const rid=getRID();
      if (!rid) return;
      console.info("[VSP] P71 force fallback rid=", rid);
      const [ds, top] = await Promise.all([
        fetchJSON("/api/vsp/datasource?rid="+encodeURIComponent(rid)),
        fetchJSON("/api/vsp/top_findings_v2?limit=8")
      ]);
      render(ds, top);
      console.info("[VSP] P71 rendered");
    }

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", function(){ setTimeout(run, 300); }, {once:true});
    } else {
      setTimeout(run, 300);
    }
  }catch(e){
    try{ console.warn("[VSP] P71 failed:", e); }catch(_){}
  }
})();
"""

# Append to end to guarantee execution even if earlier code returns
s = s.rstrip() + "\n\n" + inject + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] P71 appended force fallback renderer")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P71 applied. Hard refresh: Ctrl+Shift+R"
