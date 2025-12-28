#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_ui_4tabs_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== [1] quick BE probes =="
RID="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -r '.items[0].run_id' 2>/dev/null || true)"
echo "[RID] ${RID:-<none>}"
if [ -n "${RID:-}" ] && [ "${RID:-null}" != "null" ]; then
  echo "-- extras.kpi --"
  curl -sS "http://127.0.0.1:8910/api/vsp/dashboard_v3_extras_v1?rid=$RID" \
    | jq '{ok:.ok,rid:.rid,kpi:(.kpi|{total,effective,degraded,unknown_count,score}), keys:(keys)}' || true
  echo "-- findings.counts --"
  curl -sS "http://127.0.0.1:8910/api/vsp/findings_unified_v2/$RID?limit=1" \
    | jq '{ok,total,counts:{unknown_count:(.counts.unknown_count), by_tool_n:((.counts.by_tool|keys|length) // 0), by_sev:(.counts.by_sev)}}' || true
fi

echo
echo "== [2] ensure JS is parseable; if broken -> auto-restore latest good backup =="

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pre_kpi_fix_${TS}" && echo "[BACKUP] $F.bak_pre_kpi_fix_${TS}"

if ! node --check "$F" >/dev/null 2>&1; then
  echo "[WARN] current JS has syntax error. Searching backups..."
  pick=""
  for b in $(ls -1t "${F}".bak_* 2>/dev/null || true); do
    if node --check "$b" >/dev/null 2>&1; then
      pick="$b"
      break
    fi
  done
  if [ -z "$pick" ]; then
    echo "[ERR] no parseable backup found for $F"
    node --check "$F" || true
    exit 3
  fi
  cp -f "$pick" "$F"
  echo "[RESTORE] restored from $pick"
else
  echo "[OK] current JS parses"
fi

echo
echo "== [3] append canonical KPI hydrator (extras+findings_v2) =="

python3 - <<'PY'
from pathlib import Path
F=Path("static/js/vsp_ui_4tabs_commercial_v1.js")
s=F.read_text(encoding="utf-8", errors="ignore")
marker="VSP_KPI_HYDRATOR_CANON_P1_V1"
if marker in s:
    print("[SKIP] marker exists:", marker)
else:
    patch = r'''
/* === VSP_KPI_HYDRATOR_CANON_P1_V1 ===
   Canonical KPI hydrator:
   - RID from __VSP_RID_STATE__ OR DOM "RID:" OR hash
   - KPI from /api/vsp/dashboard_v3_extras_v1?rid=...
   - Tool+Sev from /api/vsp/findings_unified_v2/<rid>?limit=1
   - Writes #kpi-overall/#kpi-gate/#kpi-gitleaks/#kpi-codeql (+sub)
*/
;(function(){
  'use strict';

  function _el(id){ try{ return document.getElementById(id); }catch(_){ return null; } }
  function _isPlaceholder(t){
    t = (t||"").toString().trim();
    if(!t) return True;
    var u = t.toUpperCase();
    return (t==="…" || t==="—" || u==="N/A" || u==="BOOT" || u==="LOADING" || u==="PENDING");
  }
  function _hasValue(el){
    try{
      var t = (el && (el.textContent||"") || "").trim();
      if(!t) return false;
      var u=t.toUpperCase();
      return (t!=="…" && t!=="—" && u!=="N/A");
    }catch(_){ return false; }
  }
  function _unlockIfPlaceholder(id){
    var el=_el(id); if(!el) return;
    try{
      var t=(el.textContent||"").trim();
      var u=t.toUpperCase();
      var ph = (!t) || (t==="…"||t==="—"||u==="N/A"||u==="BOOT");
      if(ph) el.removeAttribute("data-vsp-kpi-lock");
    }catch(_){}
  }
  function _lockIfReal(id){
    var el=_el(id); if(!el) return;
    try{
      if(_hasValue(el)) el.setAttribute("data-vsp-kpi-lock","1");
    }catch(_){}
  }
  function _setText(id,v){
    var el=_el(id); if(!el) return false;
    try{
      if(el.getAttribute("data-vsp-kpi-lock")==="1" && _hasValue(el)) return false;
      el.textContent = (v===0) ? "0" : (v ? String(v) : "—");
      return true;
    }catch(_){ return false; }
  }

  function _normRid(x){
    try{
      x = (x||"").toString().trim();
      x = x.replace(/^RUN[_\-\s]+/i,"").replace(/^RID[:\s]+/i,"");
      var m = x.match(/(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return m[1];
      return x.replace(/\s+/g,"_");
    }catch(_){ return ""; }
  }

  function _getRid(){
    // 1) shared rid state
    try{
      var st = window.__VSP_RID_STATE__ || window.__VSP_RID_STATE || window.VSP_RID_STATE || window.__vsp_rid_state;
      if(st){
        var v = st.rid || st.run_id || (st.state && (st.state.rid || st.state.run_id));
        if(!v && typeof st.get === "function"){
          var g = st.get();
          v = g && (g.rid || g.run_id);
        }
        if(v) return _normRid(v);
      }
    }catch(_){}
    // 2) DOM contains "RID: VSP_CI_..."
    try{
      var txt = (document.body && (document.body.innerText || document.body.textContent) || "");
      var m = txt.match(/RID\s*[:=]\s*(VSP_CI_\d{8}_\d{6})/i);
      if(m && m[1]) return _normRid(m[1]);
    }catch(_){}
    // 3) hash
    try{
      var h = (location.hash||"");
      var m2 = h.match(/(VSP_CI_\d{8}_\d{6})/i);
      if(m2 && m2[1]) return _normRid(m2[1]);
    }catch(_){}
    return "";
  }

  function _fmtBySev(bySev){
    if(!bySev) return "";
    var order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"];
    var out=[];
    for(var i=0;i<order.length;i++){
      var k=order[i];
      if(bySev[k]!==undefined && bySev[k]!==null) out.push(k[0]+":"+bySev[k]);
    }
    return out.join(" ");
  }

  function _pickByTool(byTool, want){
    if(!byTool) return null;
    if(byTool[want]!==undefined) return byTool[want];
    var w = String(want||"").toUpperCase();
    var keys = Object.keys(byTool);
    for(var i=0;i<keys.length;i++){
      if(String(keys[i]||"").toUpperCase()===w) return byTool[keys[i]];
    }
    return null;
  }

  async function _fetchJson(url){
    try{
      var r = await fetch(url, {cache:"no-store"});
      if(!r.ok) return null;
      return await r.json();
    }catch(_){ return null; }
  }

  async function hydrateOnce(){
    var rid=_getRid();
    if(!rid) return false;

    var extras = await _fetchJson("/api/vsp/dashboard_v3_extras_v1?rid="+encodeURIComponent(rid));
    var fu = await _fetchJson("/api/vsp/findings_unified_v2/"+encodeURIComponent(rid)+"?limit=1");

    var total=null, eff=null, degr=null, unk=null, score=null;
    if(extras && extras.kpi){
      var k=extras.kpi||{};
      if(k.total!=null) total=k.total;
      if(k.effective!=null) eff=k.effective;
      if(k.degraded!=null) degr=k.degraded;
      if(k.unknown_count!=null) unk=k.unknown_count;
      if(k.score!=null) score=k.score;
    }

    var bySev=null, byTool=null;
    if(fu && fu.counts){
      bySev = fu.counts.by_sev || null;
      byTool = fu.counts.by_tool || null;
      if(total==null && fu.total!=null) total=fu.total;
      if(unk==null && fu.counts.unknown_count!=null) unk=fu.counts.unknown_count;
    }

    // derive missing
    if(degr==null && unk!=null) degr=unk;
    if(eff==null && total!=null && degr!=null) eff = Math.max(0, (total - degr));

    if(total==null && eff==null && degr==null && !bySev && !byTool) return false;

    var verdict = (degr && degr>0) ? "DEGRADED" : ((total && total>0) ? "OK" : "EMPTY");
    var gateTxt = (score!=null) ? (String(score)+"/100") : verdict;

    _unlockIfPlaceholder("kpi-overall");
    _unlockIfPlaceholder("kpi-gate");
    _unlockIfPlaceholder("kpi-gitleaks");
    _unlockIfPlaceholder("kpi-codeql");

    _setText("kpi-overall", verdict);
    _setText("kpi-overall-sub",
      "total "+(total==null?"—":total)+" | eff "+(eff==null?"—":eff)+" | degr "+(degr==null?"—":degr)+" | unk "+(unk==null?"—":unk)
    );
    _setText("kpi-gate", gateTxt);
    _setText("kpi-gate-sub", _fmtBySev(bySev));

    var gtl=_pickByTool(byTool,"GITLEAKS");
    var cql=_pickByTool(byTool,"CODEQL");
    _setText("kpi-gitleaks", (gtl==null) ? "NOT_RUN" : gtl);
    _setText("kpi-gitleaks-sub", "GITLEAKS");
    _setText("kpi-codeql", (cql==null) ? "NOT_RUN" : cql);
    _setText("kpi-codeql-sub", "CODEQL");

    _lockIfReal("kpi-overall");
    _lockIfReal("kpi-gate");
    _lockIfReal("kpi-gitleaks");
    _lockIfReal("kpi-codeql");
    return true;
  }

  var started=false;
  function start(){
    if(started) return;
    started=true;

    // fast warm-up loop (1s), then slow keep-alive (15s)
    var n=0;
    var t = setInterval(function(){
      n++;
      hydrateOnce().catch(function(){});
      if(n>=45){
        clearInterval(t);
        setInterval(function(){ hydrateOnce().catch(function(){}); }, 15000);
      }
    }, 1000);
  }

  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
'''
    # NOTE: avoid breaking trailing source maps; append at end
    F.write_text(s + "\n\n" + patch + "\n", encoding="utf-8")
    print("[OK] appended", marker)
PY

node --check "$F" >/dev/null
echo "[OK] node --check OK => $F"

echo
echo "== [4] restart gunicorn 8910 =="
PID="$(cat out_ci/ui_8910.pid 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  >/dev/null 2>&1 &
sleep 0.8

echo
echo "== [5] verify markers + endpoints =="
curl -sS http://127.0.0.1:8910/static/js/vsp_ui_4tabs_commercial_v1.js | grep -n "VSP_KPI_HYDRATOR_CANON_P1_V1" | head -n 5 || true

RID2="$(curl -sS 'http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1' | jq -r '.items[0].run_id' 2>/dev/null || true)"
echo "[RID2] ${RID2:-<none>}"
if [ -n "${RID2:-}" ] && [ "${RID2:-null}" != "null" ]; then
  curl -sS "http://127.0.0.1:8910/api/vsp/dashboard_v3_extras_v1?rid=$RID2" | jq '.kpi' || true
  curl -sS "http://127.0.0.1:8910/api/vsp/findings_unified_v2/$RID2?limit=1" | jq '.counts | {unknown_count, by_tool:(.by_tool|keys|length), by_sev:.by_sev}' || true
fi

echo
echo "[DONE] Open UI and HARD refresh: Ctrl+Shift+R"
