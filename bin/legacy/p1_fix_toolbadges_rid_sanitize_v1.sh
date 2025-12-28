#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_dash_only_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

cp -f "$JS" "${JS}.bak_rid_sanitize_${TS}"
echo "[BACKUP] ${JS}.bak_rid_sanitize_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

start = "/* ===================== VSP_P1_DASH_UNIFY_RELEASE_TOOLBADGES_V1 ===================== */"
end   = "/* ===================== /VSP_P1_DASH_UNIFY_RELEASE_TOOLBADGES_V1 ===================== */"

i = s.find(start)
j = s.find(end)
if i == -1 or j == -1 or j < i:
    raise SystemExit("[ERR] cannot find toolbadges marker block to replace")

j2 = j + len(end)

fixed = textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_UNIFY_RELEASE_TOOLBADGES_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const TOOLS = ["Bandit","Semgrep","Gitleaks","KICS","Trivy","Syft","Grype","CodeQL"];

    const css = `
#vsp_toollane_badges_v1{
  display:flex; gap:8px; align-items:center; flex-wrap:wrap; justify-content:center;
  margin: 6px 12px 0 12px;
  font: 12px/1.35 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
  color: rgba(255,255,255,.92);
}
.vsp_tbadge_v1{
  display:inline-flex; gap:6px; align-items:center;
  padding:6px 8px; border-radius:999px;
  border:1px solid rgba(255,255,255,.12);
  background: rgba(255,255,255,.05);
  font: 11px/1.2 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
  color: rgba(255,255,255,.92);
  cursor:pointer;
}
.vsp_tbadge_v1 .d{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.30);box-shadow:0 0 0 3px rgba(255,255,255,.06)}
.vsp_tbadge_v1.ok  .d{background:#24d17e; box-shadow:0 0 0 3px rgba(36,209,126,.12)}
.vsp_tbadge_v1.warn .d{background:#f4b400; box-shadow:0 0 0 3px rgba(244,180,0,.12)}
.vsp_tbadge_v1.err .d{background:#ff4d4f; box-shadow:0 0 0 3px rgba(255,77,79,.12)}

#vsp_toollane_modal_v1{
  position:fixed; inset:0; z-index:100000;
  background:rgba(0,0,0,.55); display:none; align-items:center; justify-content:center;
}
#vsp_toollane_modal_v1 .card{
  width:min(920px, 92vw); max-height:82vh; overflow:auto;
  border-radius:16px;
  background:rgba(10,16,32,.96);
  border:1px solid rgba(255,255,255,.12);
  box-shadow:0 18px 55px rgba(0,0,0,.55);
  padding:14px;
  color:rgba(255,255,255,.92);
  font:12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
}
#vsp_toollane_modal_v1 .top{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-bottom:8px}
#vsp_toollane_modal_v1 .ttl{font-weight:900;letter-spacing:.2px}
#vsp_toollane_modal_v1 button{
  cursor:pointer;border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.06); color:rgba(255,255,255,.92);
  padding:7px 10px;border-radius:12px;font-weight:800;
}
pre.vsp_pre_v1{
  margin:0; padding:10px; border-radius:12px;
  background:rgba(255,255,255,.05); border:1px solid rgba(255,255,255,.10);
  overflow:auto;
}
    `.trim();

    const ensureStyle = ()=>{
      if (document.getElementById("vsp_toollane_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_toollane_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const hideOldReleaseBox = ()=>{
      const el = document.getElementById("vsp_release_dl_wrap_v1");
      if (el) el.style.display = "none";
    };

    // ---------------- RID: strict validation to avoid "RID := whole page text" ----------------
    const isRid = (v)=>{
      if (!v) return false;
      v = String(v).trim();
      if (v.length < 6 || v.length > 80) return false;
      if (/\s/.test(v)) return false;
      // allow RUN_..., VSP_..., or similar tokens
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]+$/.test(v)) return false;
      // prefer having digits (runs almost always have digits)
      if (!/\d/.test(v)) return false;
      return true;
    };

    const short = (v)=>{
      v = String(v||"");
      if (v.length <= 28) return v;
      return v.slice(0,16) + "…" + v.slice(-8);
    };

    // Hook fetch once to capture rid from real traffic
    const hookFetchRid = ()=>{
      if (window.__vsp_fetch_rid_hooked_v1) return;
      window.__vsp_fetch_rid_hooked_v1 = true;
      const orig = window.fetch;
      window.fetch = async function(input, init){
        try{
          const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
          if (url && url.includes("/api/vsp/run_file_allow") && url.includes("rid=")){
            const u = new URL(url, location.origin);
            const rid = (u.searchParams.get("rid") || "").trim();
            if (isRid(rid)) window.__vsp_last_rid_v1 = rid;
          }
        }catch(e){}
        return orig.apply(this, arguments);
      };
    };

    const getPinnedRid = ()=>{
      const keys = ["vsp5_pin_rid","vsp_pin_rid","VSP_PIN_RID","vsp5.rid.pinned","vsp_last_rid","vsp5_last_rid"];
      for (const k of keys){
        const v = (localStorage.getItem(k) || "").trim();
        if (isRid(v)) return v;
      }
      return "";
    };

    const getRidFromDom = ()=>{
      // 1) common id/class selectors
      const direct = document.querySelector("#rid,#rid_input,#vsp_rid,#vsp5_rid,[data-rid],[name='rid'],.rid");
      if (direct){
        const v = (direct.value || direct.textContent || "").trim();
        if (isRid(v)) return v;
      }
      // 2) any select that looks like a run picker (options contain RUN_/VSP_)
      const sels = Array.from(document.querySelectorAll("select"));
      for (const sel of sels){
        const v = String(sel.value || "").trim();
        if (isRid(v)) return v;
        const opt = sel.querySelector("option:checked");
        if (opt){
          const ov = String(opt.value || opt.textContent || "").trim();
          if (isRid(ov)) return ov;
        }
      }
      return "";
    };

    const getRidFromApi = async ()=>{
      try{
        const r = await fetch("/api/vsp/rid_latest", { cache:"no-store" });
        const j = await r.json();
        const rid = (j && (j.rid || j.RID || (j.data && j.data.rid))) || "";
        const v = String(rid || "").trim();
        return isRid(v) ? v : "";
      }catch(e){
        return "";
      }
    };

    const getRid = async ()=>{
      const w = (window.__vsp_last_rid_v1 || "").trim();
      if (isRid(w)) return w;

      let rid = getRidFromDom();
      if (!rid) rid = getPinnedRid();
      if (!rid) rid = await getRidFromApi();
      return rid;
    };

    const fetchGateSummary = async (rid)=>{
      const url = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
      const r = await fetch(url, { cache:"no-store" });
      return await r.json();
    };

    const classify = (o)=>{
      if (!o || typeof o !== "object") return "err";
      if (o.missing || o.is_missing) return "err";
      if (o.degraded || o.is_degraded || o.status === "degraded") return "warn";
      if (o.ok === true || o.status === "ok") return "ok";
      return "warn";
    };

    const ensureModal = ()=>{
      if (document.getElementById("vsp_toollane_modal_v1")) return;
      const m=document.createElement("div");
      m.id="vsp_toollane_modal_v1";
      m.innerHTML = `
        <div class="card">
          <div class="top">
            <div class="ttl" id="vsp_toollane_modal_ttl_v1">Tool details</div>
            <button id="vsp_toollane_modal_close_v1">Close</button>
          </div>
          <pre class="vsp_pre_v1" id="vsp_toollane_modal_pre_v1">{}</pre>
        </div>
      `;
      document.body.appendChild(m);
      m.addEventListener("click",(e)=>{ if (e.target===m) m.style.display="none"; });
      document.getElementById("vsp_toollane_modal_close_v1").addEventListener("click",()=>{ m.style.display="none"; });
    };

    const showModal = (title, obj)=>{
      ensureModal();
      const m=document.getElementById("vsp_toollane_modal_v1");
      document.getElementById("vsp_toollane_modal_ttl_v1").textContent = title;
      document.getElementById("vsp_toollane_modal_pre_v1").textContent = JSON.stringify(obj || {}, null, 2);
      m.style.display="flex";
    };

    const attachBadges = ()=>{
      const cmd = document.getElementById("vsp_cmdbar_v1");
      if (!cmd) return false;
      if (document.getElementById("vsp_toollane_badges_v1")) return true;

      ensureStyle();
      hideOldReleaseBox();

      const wrap = document.createElement("div");
      wrap.id = "vsp_toollane_badges_v1";
      cmd.insertAdjacentElement("afterend", wrap);
      return true;
    };

    const getToolObj = (by, toolName)=>{
      if (!by || typeof by !== "object") return null;
      const tn = toolName.toLowerCase();
      for (const k of Object.keys(by)){
        if (k.toLowerCase() === tn) return by[k];
      }
      return by[toolName] || null;
    };

    const renderBadges = async ()=>{
      if (!attachBadges()) return;

      const wrap = document.getElementById("vsp_toollane_badges_v1");
      if (!wrap) return;

      wrap.innerHTML = `<span style="opacity:.75;font-weight:800">Tool lane:</span> <span style="opacity:.65">loading…</span>`;

      const rid = await getRid();
      if (!rid){
        wrap.innerHTML = `<span style="opacity:.75;font-weight:800">Tool lane:</span> <span style="opacity:.65">RID not ready (click Refresh/Pin or wait)</span>`;
        return;
      }

      let gs=null;
      try{
        gs = await fetchGateSummary(rid);
      }catch(e){
        wrap.innerHTML = `<span style="opacity:.75;font-weight:800">Tool lane (RID: ${short(rid)}):</span> <span style="opacity:.65">gate_summary fetch failed</span>`;
        return;
      }

      const by = (gs && (gs.by_tool || gs.tools || gs.byTool)) || {};
      wrap.innerHTML = `<span style="opacity:.75;font-weight:800">Tool lane (RID: ${short(rid)}):</span>`;

      for (const t of TOOLS){
        const obj = getToolObj(by, t);
        const st = classify(obj);

        const b=document.createElement("span");
        b.className = `vsp_tbadge_v1 ${st}`;
        b.innerHTML = `<span class="d"></span><span style="font-weight:900">${t}</span>`;
        b.title = "Click to view tool detail";
        b.addEventListener("click", ()=> showModal(`${t} • ${rid}`, obj || {}));
        wrap.appendChild(b);
      }
    };

    const boot = ()=>{
      if (!(location && location.pathname === "/vsp5")) return;
      hookFetchRid();

      let n=0;
      const timer = setInterval(()=>{
        n++;
        hideOldReleaseBox();
        const hasCmd = !!document.getElementById("vsp_cmdbar_v1");
        if (hasCmd){
          clearInterval(timer);
          renderBadges();
          setInterval(()=>{ hideOldReleaseBox(); renderBadges(); }, 60000);
        }
        if (n>120) clearInterval(timer);
      }, 250);
    };

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_TOOLBADGES_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_UNIFY_RELEASE_TOOLBADGES_V1 ===================== */
""").rstrip() + "\n"

s2 = s[:i] + fixed + s[j2:]
p.write_text(s2, encoding="utf-8")
print("[OK] replaced toolbadges block (RID sanitize + fetch-hook)")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => no long RID line; badges use real RID."
