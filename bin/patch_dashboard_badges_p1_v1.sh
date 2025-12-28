#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F1="static/js/vsp_dashboard_enhance_v1.js"
F2="static/js/dashboard_render.js"
F=""

if [ -f "$F1" ]; then F="$F1"; fi
if [ -z "$F" ] && [ -f "$F2" ]; then F="$F2"; fi
[ -n "$F" ] || { echo "[ERR] missing dashboard JS ($F1 or $F2)"; exit 2; }

cp -f "$F" "$F.bak_badges_${TS}" && echo "[BACKUP] $F.bak_badges_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("'"$F"'")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_DASH_BADGES_P1_V1"
if MARK in s:
    print("[SKIP] already patched:", p)
    raise SystemExit(0)

block = r'''
/* VSP_DASH_BADGES_P1_V1: Dashboard badges for Degraded tools + Rule Overrides delta (live RID) */
(function(){
  'use strict';

  async function _j(url, timeoutMs=6000){
    const ctrl = new AbortController();
    const t = setTimeout(()=>ctrl.abort(), timeoutMs);
    try{
      const r = await fetch(url, {signal: ctrl.signal, headers:{'Accept':'application/json'}});
      const ct = (r.headers.get('content-type')||'').toLowerCase();
      if(!ct.includes('application/json')) return null;
      return await r.json();
    }catch(e){
      return null;
    }finally{
      clearTimeout(t);
    }
  }

  function _getRidFromLocal(){
    const keys = ["vsp_selected_rid_v2","vsp_selected_rid","vsp_current_rid","VSP_RID","vsp_rid"];
    for(const k of keys){
      try{
        const v = localStorage.getItem(k);
        if(v && v !== "null" && v !== "undefined") return v;
      }catch(e){}
    }
    return null;
  }

  async function _getRid(){
    try{
      if(window.VSP_RID && typeof window.VSP_RID.get === "function"){
        const r = window.VSP_RID.get();
        if(r) return r;
      }
    }catch(e){}
    const l = _getRidFromLocal();
    if(l) return l;

    const x = await _j("/api/vsp/latest_rid_v1");
    if(x && x.ok && x.run_id) return x.run_id;
    return null;
  }

  function _findDashHost(){
    // prefer dashboard tab container
    return document.getElementById("vsp4-dashboard")
      || document.querySelector("[data-tab='dashboard']")
      || document.querySelector("#tab-dashboard")
      || document.querySelector(".vsp-dashboard")
      || document.querySelector("main")
      || document.body;
  }

  function _ensureBar(){
    const host = _findDashHost();
    if(!host) return null;

    let bar = document.getElementById("vsp-dash-p1-badges");
    if(bar) return bar;

    bar = document.createElement("div");
    bar.id = "vsp-dash-p1-badges";
    bar.style.cssText = "margin:10px 0 12px 0;padding:10px 12px;border:1px solid rgba(148,163,184,.18);border-radius:14px;background:rgba(2,6,23,.35);display:flex;gap:10px;flex-wrap:wrap;align-items:center;";

    function pill(id, label){
      const a = document.createElement("a");
      a.href="#";
      a.id=id;
      a.style.cssText = "display:inline-flex;gap:8px;align-items:center;padding:7px 10px;border-radius:999px;border:1px solid rgba(148,163,184,.22);text-decoration:none;color:#cbd5e1;font-size:12px;white-space:nowrap;";
      a.innerHTML = `<b style="font-weight:700;color:#e2e8f0">${label}</b><span style="opacity:.9" data-val>loading…</span>`;
      return a;
    }

    bar.appendChild(pill("vsp-pill-degraded","Degraded"));
    bar.appendChild(pill("vsp-pill-overrides","Overrides"));
    bar.appendChild(pill("vsp-pill-rid","RID"));

    // insert near top of dashboard host
    host.prepend(bar);
    return bar;
  }

  function _setPill(id, text){
    const a = document.getElementById(id);
    if(!a) return;
    const v = a.querySelector("[data-val]");
    if(v) v.textContent = text;
  }

  function _fmtDegraded(st){
    const arr = (st && st.degraded_tools) ? st.degraded_tools : [];
    if(!arr || !arr.length) return "none";
    // show max 4 tools
    const parts = [];
    for(const it of arr.slice(0,4)){
      const tool = it.tool || it.name || "tool";
      const rc = (it.rc !== undefined && it.rc !== null) ? `rc=${it.rc}` : "";
      const v  = it.verdict ? String(it.verdict) : "";
      const why = it.reason || it.error || it.note || "";
      const one = [tool, v, rc].filter(Boolean).join(":") + (why ? ` (${String(why).slice(0,30)})` : "");
      parts.push(one.trim());
    }
    return parts.join(" | ") + (arr.length>4 ? ` (+${arr.length-4})` : "");
  }

  function _fmtOverrides(eff){
    const d = (eff && eff.delta) ? eff.delta : {};
    const matched = d.matched_n ?? 0;
    const applied = d.applied_n ?? 0;
    const sup = d.suppressed_n ?? 0;
    const chg = d.changed_severity_n ?? 0;
    const exp = d.expired_match_n ?? 0;
    return `matched=${matched} applied=${applied} suppressed=${sup} changed=${chg} expired=${exp}`;
  }

  async function refresh(){
    _ensureBar();
    const rid = await _getRid();
    _setPill("vsp-pill-rid", rid || "n/a");
    if(!rid) return;

    const [st, eff] = await Promise.all([
      _j(`/api/vsp/run_status_v2/${encodeURIComponent(rid)}`),
      _j(`/api/vsp/findings_effective_v1/${encodeURIComponent(rid)}?limit=0`)
    ]);

    _setPill("vsp-pill-degraded", _fmtDegraded(st));
    _setPill("vsp-pill-overrides", _fmtOverrides(eff));
  }

  // click -> open drilldown panel if available
  document.addEventListener("click", function(ev){
    const a = ev.target && ev.target.closest && ev.target.closest("#vsp-pill-degraded,#vsp-pill-overrides");
    if(!a) return;
    ev.preventDefault();
    try{
      if(window.VSP_DASH_DRILLDOWN && typeof window.VSP_DASH_DRILLDOWN.open === "function"){
        window.VSP_DASH_DRILLDOWN.open();
      }
    }catch(e){}
  }, true);

  // refresh triggers
  window.addEventListener("vsp:rid_changed", function(){ refresh(); });
  window.addEventListener("hashchange", function(){ setTimeout(refresh, 120); });
  window.addEventListener("load", function(){ setTimeout(refresh, 200); });

  // initial
  setTimeout(refresh, 250);
})();
'''

# append at end
s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")
print("[OK] appended badges block to", p)
PY

node --check "$F" >/dev/null && echo "[OK] node --check OK => $F"
echo "[DONE] patch_dashboard_badges_p1_v1"
echo "Next: hard refresh browser (Ctrl+Shift+R)."
