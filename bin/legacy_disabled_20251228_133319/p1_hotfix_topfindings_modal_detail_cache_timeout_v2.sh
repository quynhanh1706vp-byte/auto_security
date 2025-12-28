#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dash_only_v1.js"
cp -f "$JS" "${JS}.bak_topux2_fix_${TS}"
echo "[BACKUP] ${JS}.bak_topux2_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_dash_only_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

start="/* ===================== VSP_P1_DASH_TOPFINDINGS_MODAL_DETAIL_DATASOURCE_V1 ===================== */"
end  ="/* ===================== /VSP_P1_DASH_TOPFINDINGS_MODAL_DETAIL_DATASOURCE_V1 ===================== */"
i=s.find(start); j=s.find(end)
if i==-1 or j==-1 or j<i:
    raise SystemExit("[ERR] cannot find marker block to replace: TOPFINDINGS_MODAL_DETAIL_DATASOURCE_V1")
j2=j+len(end)

fixed=textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_TOPFINDINGS_MODAL_DETAIL_DATASOURCE_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const isRid=(v)=>{
      if (!v) return false;
      v=String(v).trim();
      if (v.length<6||v.length>80) return false;
      if (/\s/.test(v)) return false;
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]+$/.test(v)) return false;
      if (!/\d/.test(v)) return false;
      return true;
    };
    const getPinnedRid=()=>{
      const keys=["vsp5_pin_rid","vsp_pin_rid","VSP_PIN_RID","vsp5.rid.pinned","vsp5_last_rid","vsp_last_rid"];
      for (const k of keys){
        try{
          const v=(localStorage.getItem(k)||"").trim();
          if (isRid(v)) return v;
        }catch(e){}
      }
      return "";
    };
    const getRid=()=>{
      const pin=getPinnedRid();
      if (isRid(pin)) return pin;
      const v=(window.__vsp_last_rid_v1||"").trim();
      return isRid(v)?v:"";
    };
    const runFileUrl=(rid, path)=>`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
    const norm=(v)=>String(v||"").toLowerCase().trim();

    // global cache by RID (commercial-safe)
    if (!window.__vsp_findings_cache_v2) window.__vsp_findings_cache_v2 = {};
    const cache = window.__vsp_findings_cache_v2;

    const ensureExtraButtons=()=>{
      const modal=document.getElementById("vsp_topux_modal_v1");
      if (!modal) return;
      const top=modal.querySelector(".top > div:last-child");
      if (!top) return;
      if (!document.getElementById("vsp_topux_ds_v1")){
        const b=document.createElement("button");
        b.id="vsp_topux_ds_v1";
        b.textContent="Open Data Source";
        top.insertBefore(b, top.firstChild);
      }
    };

    const openDataSource=(obj)=>{
      const q = new URLSearchParams();
      if (obj && obj.tool) q.set("tool", obj.tool);
      if (obj && obj.severity) q.set("severity", obj.severity);
      const qq = (obj && (obj.title || obj.location)) ? (obj.title || obj.location) : "";
      if (qq) q.set("q", qq.slice(0,160));
      const rid=getRid();
      if (rid) q.set("rid", rid);
      window.open("/data_source?" + q.toString(), "_blank", "noopener,noreferrer");
    };

    const setModal=(title, meta, payloadObj)=>{
      const ttl=document.getElementById("vsp_topux_ttl_v1");
      const metaEl=document.getElementById("vsp_topux_meta_v1");
      const pre=document.getElementById("vsp_topux_pre_v1");
      if (ttl) ttl.textContent = title || "Finding detail";
      if (metaEl) metaEl.textContent = meta || "";
      if (pre) pre.textContent = JSON.stringify(payloadObj||{}, null, 2);
      const m=document.getElementById("vsp_topux_modal_v1");
      if (m) m.style.display="flex";
      ensureExtraButtons();
      const ds=document.getElementById("vsp_topux_ds_v1");
      if (ds) ds.onclick = ()=>openDataSource(payloadObj || {});
    };

    const fetchFindingsCached = async (rid)=>{
      if (cache[rid] && Array.isArray(cache[rid])) return cache[rid];

      const ctrl=new AbortController();
      const to=setTimeout(()=>ctrl.abort(), 4000); // timeout 4s
      try{
        const u = runFileUrl(rid, "findings_unified.json");
        const r = await fetch(u, {cache:"no-store", signal: ctrl.signal});
        const j = await r.json();
        const arr = (j && (j.findings || j.items || j.data)) || [];
        cache[rid] = Array.isArray(arr) ? arr : [];
        return cache[rid];
      } finally {
        clearTimeout(to);
      }
    };

    const findDetailRecord = async (rowObj)=>{
      const rid=getRid();
      if (!rid) return null;
      const arr = await fetchFindingsCached(rid);
      if (!arr || !arr.length) return null;

      const wantTool=norm(rowObj.tool);
      const wantSev=norm(rowObj.severity);
      const wantTitle=norm(rowObj.title);
      const wantLoc=norm(rowObj.location);

      const N = Math.min(arr.length, 2000);
      let best=null; let bestScore=-1;
      for (let i=0;i<N;i++){
        const f=arr[i]||{};
        const ftool=norm(f.tool||f.source||f.engine);
        if (wantTool && ftool && ftool!==wantTool) continue;

        const fsev=norm(f.severity||f.sev||f.level);
        const ftitle=norm(f.title||f.message||f.rule_name||f.rule||"");
        const floc=norm(f.location||f.path||f.file||"");

        let score=0;
        if (wantSev && fsev===wantSev) score+=2;
        if (wantTitle && ftitle && (ftitle===wantTitle || ftitle.includes(wantTitle.slice(0,80)))) score+=5;
        if (wantLoc && floc && (floc===wantLoc || floc.includes(wantLoc.slice(0,80)))) score+=5;

        if (score>bestScore){
          bestScore=score; best=f;
        }
        if (score>=9) break; // good enough
      }
      if (bestScore>=5) return best;
      return null;
    };

    const attach=()=>{
      const tables=[...document.querySelectorAll("table")];
      let topTable=null;
      for (const t of tables){
        const th=[...t.querySelectorAll("th")].map(x=>(x.textContent||"").trim().toLowerCase());
        if (th.includes("severity") && th.includes("tool") && th.includes("title") && th.includes("location")) { topTable=t; break; }
      }
      if (!topTable) return false;

      // prevent multiple attaches
      if (topTable.__vsp_topux2_attached) return true;
      topTable.__vsp_topux2_attached = true;

      topTable.addEventListener("click", async (e)=>{
        const tr = e.target && e.target.closest && e.target.closest("tr");
        if (!tr) return;
        const td = tr.querySelectorAll("td");
        if (!td || td.length<4) return;

        const modal=document.getElementById("vsp_topux_modal_v1");
        const pre=document.getElementById("vsp_topux_pre_v1");
        if (!modal || !pre) return;

        // stop other handlers
        e.stopPropagation();
        e.preventDefault();

        const rowObj={
          severity:(td[0].textContent||"").trim(),
          tool:(td[1].textContent||"").trim(),
          title:(td[2].textContent||"").trim(),
          location:(td[3].textContent||"").trim(),
        };
        const rid=getRid();
        const meta = `${rowObj.severity} • ${rowObj.tool} • ${rowObj.location} ${rid?("• RID "+rid):""}`.trim();
        setModal("Finding detail (loading…)", meta, rowObj);

        try{
          const detail = await findDetailRecord(rowObj);
          if (detail){
            const merged = Object.assign({}, rowObj, detail);
            setModal("Finding detail (full)", meta, merged);
          } else {
            setModal("Finding detail (basic)", meta, rowObj);
          }
        }catch(err){
          setModal("Finding detail (basic)", meta + " • detail fetch failed/timeout", rowObj);
        }
      }, true);

      return true;
    };

    const boot=()=>{
      if (!(location && location.pathname==="/vsp5")) return;
      let n=0;
      const t=setInterval(()=>{
        n++;
        if (attach()) clearInterval(t);
        if (n>160) clearInterval(t);
      }, 250);
    };

    if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_TOPFINDINGS_MODAL_DETAIL_DS_V2] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_TOPFINDINGS_MODAL_DETAIL_DATASOURCE_V1 ===================== */
""").rstrip()+"\n"

p.write_text(s[:i] + fixed + s[j2:], encoding="utf-8")
print("[OK] replaced TOPFINDINGS modal detail block with cache+timeout v2")
PY

node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => modal detail uses cache+timeout; no lag when clicking many rows."
