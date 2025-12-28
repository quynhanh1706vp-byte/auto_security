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

cp -f "$JS" "${JS}.bak_autorefresh_${TS}"
echo "[BACKUP] ${JS}.bak_autorefresh_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DASH_AUTOLATEST_AUTOREFRESH_GATECHIP_V1"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== VSP_P1_DASH_AUTOLATEST_AUTOREFRESH_GATECHIP_V1 ===================== */
(()=> {
  try{
    if (!(location && location.pathname === "/vsp5")) return;

    const css = `
#vsp_gatechip_v1{
  display:inline-flex; align-items:center; gap:6px;
  padding:4px 8px; border-radius:999px;
  border:1px solid rgba(255,255,255,.14);
  background: rgba(255,255,255,.05);
  font-weight:900; letter-spacing:.2px;
}
#vsp_gatechip_v1 .d{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.35);box-shadow:0 0 0 3px rgba(255,255,255,.06)}
#vsp_gatechip_v1.pass .d{background:#24d17e; box-shadow:0 0 0 3px rgba(36,209,126,.12)}
#vsp_gatechip_v1.fail .d{background:#ff4d4f; box-shadow:0 0 0 3px rgba(255,77,79,.12)}
#vsp_gatechip_v1.deg  .d{background:#f4b400; box-shadow:0 0 0 3px rgba(244,180,0,.12)}
#vsp_gatechip_v1 .t{opacity:.92}
#vsp_gatechip_v1 .s{opacity:.72; font-weight:800}
    `.trim();

    const ensureStyle = ()=>{
      if (document.getElementById("vsp_gatechip_style_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_gatechip_style_v1";
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

    const short = (v)=>{
      v = String(v||"");
      if (v.length <= 28) return v;
      return v.slice(0,16) + "…" + v.slice(-8);
    };

    // best-effort: use existing rid_latest if server has it; fallback to localStorage last rid
    const getRidLatest = async ()=>{
      try{
        const r = await fetch("/api/vsp/rid_latest", { cache:"no-store" });
        const j = await r.json();
        const rid = (j && (j.rid || j.RID || (j.data && j.data.rid))) || "";
        const v = String(rid||"").trim();
        return isRid(v) ? v : "";
      }catch(e){ return ""; }
    };

    const setPinnedRid = (rid)=>{
      if (!isRid(rid)) return;
      // write a couple of likely keys so your existing UI picks it up
      try{ localStorage.setItem("vsp5_pin_rid", rid); }catch(e){}
      try{ localStorage.setItem("vsp_pin_rid", rid); }catch(e){}
      try{ localStorage.setItem("VSP_PIN_RID", rid); }catch(e){}
      try{ localStorage.setItem("vsp5.rid.pinned", rid); }catch(e){}
      try{ localStorage.setItem("vsp5_last_rid", rid); }catch(e){}
    };

    const ensureGateChip = ()=>{
      const cmd = document.getElementById("vsp_cmdbar_v1");
      if (!cmd) return null;
      ensureStyle();
      if (document.getElementById("vsp_gatechip_v1")) return document.getElementById("vsp_gatechip_v1");

      // place chip near left side next to env
      const lhs = cmd.querySelector(".lhs") || cmd;
      const chip = document.createElement("span");
      chip.id = "vsp_gatechip_v1";
      chip.className = "";
      chip.innerHTML = `<span class="d"></span><span class="t">GATE</span><span class="s" id="vsp_gatechip_txt_v1">—</span>`;
      lhs.appendChild(chip);
      return chip;
    };

    const setGate = (mode, text)=>{
      const chip = ensureGateChip();
      if (!chip) return;
      chip.classList.remove("pass","fail","deg");
      if (mode) chip.classList.add(mode);
      const t = document.getElementById("vsp_gatechip_txt_v1");
      if (t) t.textContent = text || "—";
    };

    const fetchGate = async (rid)=>{
      // prefer run_gate.json (overall verdict), fallback to run_gate_summary.json
      const u1 = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate.json`;
      const u2 = `/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=run_gate_summary.json`;
      let j=null;
      try{
        const r = await fetch(u1, {cache:"no-store"});
        j = await r.json();
        if (j && j.ok !== False && j.ok !== false) return {src:"run_gate.json", j};
      }catch(e){}
      try{
        const r = await fetch(u2, {cache:"no-store"});
        j = await r.json();
        return {src:"run_gate_summary.json", j};
      }catch(e){}
      return {src:"", j:null};
    };

    const computeGateText = (obj)=>{
      // be conservative: parse common fields
      if (!obj) return {mode:"deg", txt:"UNKNOWN"};
      const j = obj;
      const overall = j.overall || j.verdict || j.status || (j.gate && j.gate.overall) || "";
      const degraded = j.degraded || j.is_degraded || (j.gate && j.gate.degraded) || false;
      const pass = (overall && String(overall).toLowerCase().includes("pass")) || (j.pass === true) || (j.ok === true);
      const fail = (overall && String(overall).toLowerCase().includes("fail")) || (j.fail === true);

      if (fail) return {mode:"fail", txt:"FAIL"};
      if (pass && degraded) return {mode:"deg", txt:"PASS (DEG)"};
      if (pass) return {mode:"pass", txt:"PASS"};
      if (degraded) return {mode:"deg", txt:"DEGRADED"};
      return {mode:"deg", txt:String(overall || "UNKNOWN").toUpperCase().slice(0,18)};
    };

    const clickIfExists = (text)=>{
      const btns = Array.from(document.querySelectorAll("button"));
      const b = btns.find(x => (x.textContent||"").trim().toLowerCase() === text.toLowerCase());
      if (b) { try{ b.click(); return true; }catch(e){} }
      return false;
    };

    // Try to trigger existing dashboard refresh flow (so KPIs update)
    const refreshDashboard = ()=>{
      // Your UI has Refresh / Pin RID buttons; best-effort click Refresh
      if (clickIfExists("Refresh")) return true;
      return false;
    };

    const autoLoop = async ()=>{
      // 1) auto-pick latest RID if available
      const rid = await getRidLatest();
      if (isRid(rid)) setPinnedRid(rid);

      // 2) trigger existing refresh (KPIs/top findings state)
      refreshDashboard();

      // 3) compute gate chip based on latest rid if we have it
      const rid2 = rid || (window.__vsp_last_rid_v1 || "") || "";
      const rid_use = isRid(rid2) ? rid2 : "";
      if (rid_use){
        const {j} = await fetchGate(rid_use);
        const g = computeGateText(j);
        setGate(g.mode, g.txt);
      }else{
        setGate("deg", "RID?");
      }
    };

    const boot = ()=>{
      if (!(location && location.pathname === "/vsp5")) return;
      // wait for cmdbar then attach
      let n=0;
      const t = setInterval(()=>{
        n++;
        if (document.getElementById("vsp_cmdbar_v1")){
          clearInterval(t);
          autoLoop();
          // light polling: 60s
          setInterval(autoLoop, 60000);
        }
        if (n>120) clearInterval(t);
      }, 250);
    };

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot, {once:true});
    else boot();

  }catch(e){
    console.error("[VSP_AUTOREFRESH_V1] fatal", e);
  }
})();
/* ===================== /VSP_P1_DASH_AUTOLATEST_AUTOREFRESH_GATECHIP_V1 ===================== */
""").rstrip() + "\n"

p.write_text(s + "\n\n" + addon, encoding="utf-8")
print("[OK] appended", MARK)
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null && echo "[OK] node --check: $JS" || { echo "[ERR] node --check failed"; exit 3; }
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] Hard refresh /vsp5 => Gate chip appears + auto latest RID + auto refresh every 60s."
