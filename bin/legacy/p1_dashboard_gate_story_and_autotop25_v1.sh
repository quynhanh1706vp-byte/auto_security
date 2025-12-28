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

cp -f "$JS" "${JS}.bak_gatestory_${TS}"
echo "[BACKUP] ${JS}.bak_gatestory_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_GATE_STORY_AUTOTOP25_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_GATE_STORY_AUTOTOP25_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const css = `
#vsp_gatestory_v1{
  margin: 10px 12px 10px 12px;
  border-radius: 16px;
  background: rgba(255,255,255,.03);
  border: 1px solid rgba(255,255,255,.10);
  box-shadow: 0 14px 36px rgba(0,0,0,.25);
  padding: 10px 12px;
  color: rgba(255,255,255,.92);
  font: 12px/1.4 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Arial;
}
#vsp_gatestory_v1 .row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
#vsp_gatestory_v1 .ttl{font-weight:900;letter-spacing:.2px}
#vsp_gatestory_v1 .chip{
  display:inline-flex;gap:6px;align-items:center;
  padding:4px 8px;border-radius:999px;
  border:1px solid rgba(255,255,255,.14);
  background:rgba(255,255,255,.05);
  font-weight:900;
}
#vsp_gatestory_v1 .dot{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.35);box-shadow:0 0 0 3px rgba(255,255,255,.06)}
#vsp_gatestory_v1 .pass .dot{background:#24d17e; box-shadow:0 0 0 3px rgba(36,209,126,.12)}
#vsp_gatestory_v1 .fail .dot{background:#ff4d4f; box-shadow:0 0 0 3px rgba(255,77,79,.12)}
#vsp_gatestory_v1 .deg  .dot{background:#f4b400; box-shadow:0 0 0 3px rgba(244,180,0,.12)}
#vsp_gatestory_v1 .muted{opacity:.72}
#vsp_gatestory_v1 a{color:rgba(255,255,255,.88); text-decoration:none}
#vsp_gatestory_v1 a:hover{text-decoration:underline}
    `.trim();

    const ensureStyle = ()=>{
      if (document.getElementById("vsp_gatestory_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_gatestory_style_v1";
      st.textContent=css;
      document.head.appendChild(st);
    };

    const isRid = (v)=>{
      if (!v) return false;
      v = String(v).trim();
      if (v.length < 6 || v.length > 80) return false;
      if (/\s/.test(v)) return false;
      if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]+$/.test(v)) return false;
      if (!/\d/.test(v)) return false;
      return true;
    };

    const getRid = ()=>{
      const v = (window.__vsp_last_rid_v1 || "").trim();
      return isRid(v) ? v : "";
    };

    const pickAnchor = ()=>{
      // put below cmdbar if exists, else top of body
      const cmd = document.getElementById("vsp_cmdbar_v1");
      if (cmd) return cmd;
      return document.body;
    };

    const ensurePanel = ()=>{
      ensureStyle();
      if (document.getElementById("vsp_gatestory_v1")) return document.getElementById("vsp_gatestory_v1");
      const a = pickAnchor();
      const p = document.createElement("div");
      p.id="vsp_gatestory_v1";
      p.innerHTML = `
        <div class="row">
          <div class="ttl">Gate story</div>
          <span class="chip deg" id="vsp_gs_chip_v1"><span class="dot"></span><span id="vsp_gs_txt_v1">—</span></span>
          <span class="muted" id="vsp_gs_rid_v1"></span>
          <span class="muted" id="vsp_gs_reasons_v1">loading…</span>
        </div>
        <div class="row" style="margin-top:6px">
          <span class="muted">Quick:</span>
          <a href="#" id="vsp_gs_open_summary_v1">run_gate_summary.json</a>
          <span class="muted">•</span>
          <a href="#" id="vsp_gs_open_gate_v1">run_gate.json</a>
        </div>
      `;
      a.insertAdjacentElement("afterend", p);
      return p;
    };

    const setChip = (mode, text)=>{
      const c = document.getElementById("vsp_gs_chip_v1");
      const t = document.getElementById("vsp_gs_txt_v1");
      if (!c || !t) return;
      c.classList.remove("pass","fail","deg");
      c.classList.add(mode || "deg");
      t.textContent = text || "—";
    };

    const summarizeReasons = (gs)=>{
      // try common shapes
      const reasons = [];
      try{
        const by = (gs && (gs.by_tool || gs.tools || gs.byTool)) || {};
        for (const k of Object.keys(by)){
          const o = by[k] || {};
          if (o.missing || o.is_missing) reasons.push(`${k}: missing`);
          else if (o.degraded || o.is_degraded || o.status==="degraded") reasons.push(`${k}: degraded`);
        }
      }catch(e){}

      const counts = (gs && (gs.counts_total || (gs.meta && gs.meta.counts_by_severity) || gs.counts_by_severity)) || null;
      if (counts && typeof counts === "object"){
        const c = counts.CRITICAL || counts.critical || 0;
        const h = counts.HIGH || counts.high || 0;
        if (Number(c) > 0) reasons.unshift(`CRITICAL=${c}`);
        if (Number(h) > 0) reasons.unshift(`HIGH=${h}`);
      }
      if (!reasons.length) return "No major issues detected";
      return reasons.slice(0,4).join(" • ");
    };

    const fetchJson = async (rid, path)=>{
      const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
      const r = await fetch(u, {cache:"no-store"});
      return await r.json();
    };

    const openRunFile = (rid, path)=>{
      const u = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(path)}`;
      window.open(u, "_blank", "noopener,noreferrer");
    };

    const autoClickTop25 = ()=>{
      // find the button you already have
      const btns = Array.from(document.querySelectorAll("button"));
      const b = btns.find(x => (x.textContent||"").includes("Load top findings"));
      if (b) { try{ b.click(); return true; }catch(e){} }
      return false;
    };

    let lastRid = "";

    const tick = async ()=>{
      const rid = getRid();
      if (!rid){ ensurePanel(); return; }

      ensurePanel();

      const ridEl = document.getElementById("vsp_gs_rid_v1");
      if (ridEl) ridEl.textContent = `RID: ${rid}`;

      const linkS = document.getElementById("vsp_gs_open_summary_v1");
      const linkG = document.getElementById("vsp_gs_open_gate_v1");
      if (linkS) linkS.onclick = (e)=>{ e.preventDefault(); openRunFile(rid, "run_gate_summary.json"); };
      if (linkG) linkG.onclick = (e)=>{ e.preventDefault(); openRunFile(rid, "run_gate.json"); };

      // if RID changed -> auto click Top25 once
      if (rid !== lastRid){
        lastRid = rid;
        setTimeout(()=>autoClickTop25(), 600);
      }

      // compute gate chip
      let gate = null;
      try{ gate = await fetchJson(rid, "run_gate.json"); }catch(e){}
      let gs = null;
      try{ gs = await fetchJson(rid, "run_gate_summary.json"); }catch(e){}

      // choose text
      const pass = gate && (gate.pass === true || gate.ok === true || String(gate.overall||"").toLowerCase().includes("pass"));
      const fail = gate && (gate.fail === true || String(gate.overall||"").toLowerCase().includes("fail"));
      const degraded = (gate && (gate.degraded || gate.is_degraded)) || (gs && (gs.degraded || gs.is_degraded)) || false;

      if (fail) setChip("fail", "FAIL");
      else if (pass && degraded) setChip("deg", "PASS (DEG)");
      else if (pass) setChip("pass", "PASS");
      else if (degraded) setChip("deg", "DEGRADED");
      else setChip("deg", String((gate && gate.overall) || "UNKNOWN").toUpperCase().slice(0,18));

      const rEl = document.getElementById("vsp_gs_reasons_v1");
      if (rEl) rEl.textContent = summarizeReasons(gs);
    };

    const boot = ()=>{
      if (!(location && location.pathname === "/vsp5")) return;
      // wait cmdbar exists for best placement
      let n=0;
      const t = setInterval(()=>{
        n++;
        if (document.getElementById("vsp_cmdbar_v1")){
          clearInterval(t);
          tick();
          setInterval(tick, 30000); // 30s (lighter than 60s heavy)
        }
        if (n>120) clearInterval(t);
      }, 250);
    };

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_GATE_STORY_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_GATE_STORY_AUTOTOP25_V1 ===================== */
""").rstrip() + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Gate story panel + auto load Top25 when RID changes."
