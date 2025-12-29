#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

OPS_JS="static/js/vsp_ops_panel_v1.js"
SET_JS="static/js/vsp_c_settings_v1.js"

backup(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_p916b_${TS}"
  echo "[OK] backup => ${f}.bak_p916b_${TS}"
}

backup "$OPS_JS"
backup "$SET_JS"

echo "== [P916B] write ops panel js (anti-truncate) =="
python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_ops_panel_v1.js")
lines = [
'// P916B_OPS_PANEL (safe mount + no-crash)',
'(function(){',
'  "use strict";',
'  const API="/api/vsp/ops_latest_v1";',
'  function esc(s){',
'    if(s===null||s===undefined) return "";',
'    return String(s).replace(/[&<>"]/g,c=>({ "&":"&amp;","<":"&lt;",">":"&gt;","\\"":"&quot;" }[c]));',
'  }',
'  function mk(tag, cls){',
'    const e=document.createElement(tag);',
'    if(cls) e.className=cls;',
'    return e;',
'  }',
'  function pill(text, ok){',
'    const s=mk("span","vsp-pill");',
'    s.textContent=text;',
'    s.style.display="inline-block";',
'    s.style.padding="2px 8px";',
'    s.style.borderRadius="999px";',
'    s.style.fontSize="11px";',
'    s.style.border="1px solid rgba(255,255,255,.12)";',
'    s.style.background= ok ? "rgba(34,197,94,.12)" : "rgba(245,158,11,.12)";',
'    s.style.color= ok ? "rgba(134,239,172,.95)" : "rgba(253,230,138,.95)";',
'    return s;',
'  }',
'  function kv(k,v){',
'    const row=mk("div");',
'    row.style.display="flex";',
'    row.style.gap="10px";',
'    row.style.padding="6px 0";',
'    row.style.borderBottom="1px solid rgba(255,255,255,.06)";',
'    const kk=mk("div"); kk.textContent=k; kk.style.minWidth="160px"; kk.style.opacity=".85"; kk.style.fontSize="12px";',
'    const vv=mk("div"); vv.style.fontSize="12px"; vv.style.wordBreak="break-word";',
'    vv.innerHTML = (v===null||v===undefined||v==="") ? \'<span style="opacity:.55">(none)</span>\' : esc(v);',
'    row.appendChild(kk); row.appendChild(vv);',
'    return row;',
'  }',
'  function findHost(){',
'    let host=document.getElementById("vsp_ops_panel");',
'    if(host) return host;',
'    // fallback: attach to settings page main container',
'    const main=document.querySelector("main") || document.querySelector("#vsp_root") || document.body;',
'    host=mk("div");',
'    host.id="vsp_ops_panel";',
'    host.style.marginTop="14px";',
'    main.appendChild(host);',
'    return host;',
'  }',
'  async function getJSON(){',
'    const r=await fetch(API,{cache:"no-store"});',
'    const t=await r.text();',
'    let j=null;',
'    try{ j = t ? JSON.parse(t) : null; }catch(e){ j=null; }',
'    return {status:r.status, ok:r.ok, text:t, json:j};',
'  }',
'  function render(host,p){',
'    host.innerHTML="";',
'    const wrap=mk("div");',
'    wrap.style.padding="12px";',
'    wrap.style.border="1px solid rgba(255,255,255,.08)";',
'    wrap.style.borderRadius="14px";',
'    wrap.style.background="rgba(255,255,255,.03)";',
'    const head=mk("div"); head.style.display="flex"; head.style.justifyContent="space-between"; head.style.alignItems="center"; head.style.gap="10px";',
'    const left=mk("div");',
'    const t=mk("div"); t.textContent="Ops Status (CIO)"; t.style.fontWeight="600"; t.style.fontSize="13px";',
'    const sub=mk("div"); sub.style.fontSize="12px"; sub.style.opacity=".75";',
'    const rel=(p.json && p.json.source && p.json.source.release_dir) ? p.json.source.release_dir : "";',
'    sub.innerHTML = "Evidence dir: <span style=\\"opacity:.95\\">"+esc(rel||"(unknown)")+"</span>";',
'    left.appendChild(t); left.appendChild(sub);',
'    const okBool = p.json ? !!p.json.ok : false;',
'    const right=mk("div"); right.appendChild(pill(okBool?"OK":"DEGRADED", okBool));',
'    head.appendChild(left); head.appendChild(right);',
'    const grid=mk("div"); grid.style.display="grid"; grid.style.gridTemplateColumns="1fr 1fr"; grid.style.gap="14px"; grid.style.marginTop="10px";',
'    function box(){ const b=mk("div"); b.style.padding="10px"; b.style.border="1px solid rgba(255,255,255,.08)"; b.style.borderRadius="12px"; b.style.background="rgba(0,0,0,.18)"; return b; }',
'    const L=box(), R=box();',
'    const j=p.json||{}; const src=j.source||{};',
'    L.appendChild(kv("service", j.service||src.service||j.unit||"(unknown)"));',
'    L.appendChild(kv("base", j.base||src.base||location.origin));',
'    L.appendChild(kv("http_code", j.http_code||j.code||src.http_code||String(p.status||"")));',
'    L.appendChild(kv("stamp_ts", j.ts||src.ts||"(n/a)"));',
'    const degraded = j.degraded_tools || j.degraded || src.degraded_tools || [];',
'    const tools = Array.isArray(degraded) ? degraded : (degraded && typeof degraded==="object" ? Object.keys(degraded) : []);',
'    R.appendChild(kv("degraded_tools", tools.length?tools.join(", "):"(none)"));',
'    R.appendChild(kv("release_sha", j.release_sha||""));',
'    R.appendChild(kv("release_pkg", j.release_pkg||src.release_pkg||""));',
'    grid.appendChild(L); grid.appendChild(R);',
'    const bar=mk("div"); bar.style.display="flex"; bar.style.gap="10px"; bar.style.marginTop="10px";',
'    function btn(label){ const b=mk("button"); b.textContent=label; b.style.padding="6px 10px"; b.style.borderRadius="10px"; b.style.border="1px solid rgba(255,255,255,.12)"; b.style.background="rgba(255,255,255,.04)"; b.style.color="rgba(255,255,255,.9)"; b.style.cursor="pointer"; b.style.fontSize="12px"; return b; }',
'    const bR=btn("Refresh");',
'    const bJ=btn("View JSON");',
'    const pre=mk("pre");',
'    pre.style.display="none"; pre.style.marginTop="10px"; pre.style.padding="10px"; pre.style.borderRadius="12px"; pre.style.border="1px solid rgba(255,255,255,.08)"; pre.style.background="rgba(0,0,0,.25)"; pre.style.maxHeight="260px"; pre.style.overflow="auto"; pre.style.fontSize="11px"; pre.textContent=p.text||"";',
'    bR.onclick=async()=>{ host.style.opacity=".8"; try{ const n=await getJSON(); render(host,n);} finally{host.style.opacity="1";} };',
'    bJ.onclick=()=>{ pre.style.display=(pre.style.display==="none")?"block":"none"; };',
'    bar.appendChild(bR); bar.appendChild(bJ);',
'    wrap.appendChild(head); wrap.appendChild(grid); wrap.appendChild(bar); wrap.appendChild(pre);',
'    host.appendChild(wrap);',
'  }',
'  async function ensureMounted(){',
'    const host=findHost();',
'    try{ const p=await getJSON(); render(host,p); return true; }',
'    catch(e){ host.innerHTML=\'<div style="opacity:.85;font-size:12px">Ops panel failed to load</div>\'; return false; }',
'  }',
'  window.VSPOpsPanel={ ensureMounted };',
'  if(document.readyState==="loading"){ document.addEventListener("DOMContentLoaded",()=>ensureMounted()); }',
'  else { ensureMounted(); }',
'})();',
]
p.write_text("\n".join(lines)+"\n", encoding="utf-8")
print("[OK] wrote", p)
PY

echo "== [P916B] patch settings js to auto-load + mount ops panel =="
python3 - <<'PY'
from pathlib import Path
import re, datetime

F=Path("static/js/vsp_c_settings_v1.js")
s=F.read_text(encoding="utf-8", errors="replace")

tag="P916B_SETTINGS_AUTOMOUNT_OPS"
if tag in s:
    print("[OK] already patched", tag)
    raise SystemExit(0)

# anchor: after console log "[settings:p405] rendered"
anchor = r'console\.log\(\s*\[\s*["\']settings:p405["\']\s*\]\s*rendered\s*\)'
m=re.search(anchor, s)
if not m:
    # fallback anchor: end of file
    insert_pos=len(s)
else:
    # insert after line containing it
    line_end = s.find("\n", m.end())
    insert_pos = line_end if line_end!=-1 else m.end()

inject = r'''
// P916B_SETTINGS_AUTOMOUNT_OPS
try{
  (function(){
    function loadOnce(src, cb){
      try{
        if(window.VSPOpsPanel && window.VSPOpsPanel.ensureMounted){ cb(); return; }
        if(document.querySelector('script[data-vsp-ops="1"]')){ setTimeout(cb, 50); return; }
        var sc=document.createElement("script");
        sc.src=src;
        sc.async=true;
        sc.setAttribute("data-vsp-ops","1");
        sc.onload=function(){ cb(); };
        sc.onerror=function(){ console.warn("[P916B] ops script load failed"); };
        document.head.appendChild(sc);
      }catch(e){ console.warn("[P916B] loadOnce err", e); }
    }
    loadOnce("/static/js/vsp_ops_panel_v1.js?v="+Date.now(), function(){
      try{
        if(window.VSPOpsPanel && window.VSPOpsPanel.ensureMounted){
          console.log("[P916B] ops panel mount");
          window.VSPOpsPanel.ensureMounted();
        }
      }catch(e){ console.warn("[P916B] mount err", e); }
    });
  })();
}catch(e){ console.warn("[P916B] inject err", e); }
'''

s2 = s[:insert_pos] + inject + s[insert_pos:]
F.write_text(s2, encoding="utf-8")
print("[OK] patched", F)
PY

echo "== [P916B] restart =="
sudo systemctl restart "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== [P916B] quick verify (ops_latest) =="
curl -fsS "$BASE/api/vsp/ops_latest_v1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print("ok=",j.get("ok"),"release_dir=", (j.get("source") or {}).get("release_dir"))'
echo "Open: $BASE/c/settings  (Ctrl+Shift+R hard refresh)"
