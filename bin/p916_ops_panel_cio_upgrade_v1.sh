#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_ops_panel_v1.js"

cp -f "$F" "${F}.bak_p916_${TS}" 2>/dev/null || true
echo "[OK] backup => ${F}.bak_p916_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_ops_panel_v1.js")
js=r"""
// P916_OPS_PANEL_CIO (safe, no-crash)
// Renders /api/vsp/ops_latest_v1 into a CIO-friendly card.
// Will NOT throw if JSON missing fields.

(function(){
  "use strict";

  const API = "/api/vsp/ops_latest_v1";

  function esc(s){
    if(s===null || s===undefined) return "";
    return String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
  }
  function el(tag, attrs, text){
    const e=document.createElement(tag);
    if(attrs){
      for(const k of Object.keys(attrs)){
        if(k==="class") e.className=attrs[k];
        else if(k==="html") e.innerHTML=attrs[k];
        else e.setAttribute(k, attrs[k]);
      }
    }
    if(text!==undefined && text!==null) e.textContent=text;
    return e;
  }
  function pill(text, ok){
    const p=el("span",{class:"vsp-pill"},text);
    p.style.display="inline-block";
    p.style.padding="2px 8px";
    p.style.borderRadius="999px";
    p.style.fontSize="11px";
    p.style.letterSpacing=".2px";
    p.style.border="1px solid rgba(255,255,255,.12)";
    p.style.background= ok ? "rgba(34,197,94,.12)" : "rgba(245,158,11,.12)";
    p.style.color= ok ? "rgba(134,239,172,.95)" : "rgba(253,230,138,.95)";
    return p;
  }
  function kvRow(k, v){
    const row=el("div",{class:"vsp-kv"});
    row.style.display="flex";
    row.style.gap="10px";
    row.style.alignItems="baseline";
    row.style.padding="6px 0";
    row.style.borderBottom="1px solid rgba(255,255,255,.06)";
    const kk=el("div",{class:"vsp-k"},k);
    kk.style.minWidth="160px";
    kk.style.opacity=".85";
    kk.style.fontSize="12px";
    const vv=el("div",{class:"vsp-v"});
    vv.style.fontSize="12px";
    vv.style.wordBreak="break-word";
    vv.innerHTML = (v===undefined || v===null) ? '<span style="opacity:.55">(none)</span>' : esc(v);
    row.appendChild(kk); row.appendChild(vv);
    return row;
  }
  function findOrCreateHost(){
    // preferred host created by Settings patch
    let host=document.getElementById("vsp_ops_panel");
    if(host) return host;

    // fallback: search existing "Ops Status" card and inject a host div
    const hs=[...document.querySelectorAll("h2,h3,div")];
    const h=hs.find(x => (x.textContent||"").trim().toLowerCase()==="ops status" || (x.textContent||"").toLowerCase().includes("ops status"));
    if(h){
      const card = h.closest(".card") || h.parentElement;
      if(card){
        host=el("div",{id:"vsp_ops_panel"});
        card.appendChild(host);
        return host;
      }
    }
    return null;
  }

  async function fetchJson(){
    const r = await fetch(API, {cache:"no-store"});
    const txt = await r.text();
    let j=null;
    try{ j = txt ? JSON.parse(txt) : null; }catch(e){ j=null; }
    return {ok:r.ok, status:r.status, text:txt, json:j};
  }

  function render(host, payload){
    host.innerHTML="";
    const head=el("div");
    head.style.display="flex";
    head.style.justifyContent="space-between";
    head.style.alignItems="center";
    head.style.gap="10px";

    const left=el("div");
    const title=el("div",null,"Ops Status");
    title.style.fontWeight="600";
    title.style.fontSize="13px";
    title.style.marginBottom="4px";
    const sub=el("div");
    sub.style.fontSize="12px";
    sub.style.opacity=".75";
    const relDir = payload?.json?.source?.release_dir || payload?.json?.source?.release || payload?.json?.release_dir;
    sub.innerHTML = `Evidence dir: <span style="opacity:.95">${esc(relDir||"(unknown)")}</span>`;
    left.appendChild(title); left.appendChild(sub);

    const right=el("div");
    const okVal = !!(payload?.json && payload.json.ok===True) ? True : (payload?.json ? !!payload.json.ok : false);
    // above line can’t use True in JS; keep safe:
    const okBool = payload?.json ? !!payload.json.ok : false;
    right.appendChild(pill(okBool ? "OK" : "DEGRADED", okBool));

    head.appendChild(left); head.appendChild(right);

    const grid=el("div");
    grid.style.marginTop="10px";
    grid.style.display="grid";
    grid.style.gridTemplateColumns="1fr 1fr";
    grid.style.gap="14px";

    const boxL=el("div");
    boxL.style.padding="10px";
    boxL.style.border="1px solid rgba(255,255,255,.08)";
    boxL.style.borderRadius="12px";
    boxL.style.background="rgba(255,255,255,.03)";

    const boxR=el("div");
    boxR.style.padding="10px";
    boxR.style.border="1px solid rgba(255,255,255,.08)";
    boxR.style.borderRadius="12px";
    boxR.style.background="rgba(255,255,255,.03)";

    const j = payload.json || {};
    const src = j.source || {};

    // LEFT: key runtime info
    boxL.appendChild(kvRow("service", j.service || src.service || j.unit || "(unknown)"));
    boxL.appendChild(kvRow("base", j.base || src.base || location.origin));
    boxL.appendChild(kvRow("listen", (j.listen!==undefined)? j.listen : (j.port?(":"+j.port):"(unknown)")));
    boxL.appendChild(kvRow("http_code", j.http_code || j.code || src.http_code || "(n/a)"));
    boxL.appendChild(kvRow("stamp_ts", j.ts || j.stamp_ts || src.ts || "(n/a)"));

    // RIGHT: degraded/tools + quick notes
    const degraded = j.degraded || j.degraded_tools || src.degraded_tools || [];
    const tools = Array.isArray(degraded) ? degraded : (typeof degraded==="object" && degraded ? Object.keys(degraded) : []);
    boxR.appendChild(kvRow("degraded_tools", tools.length ? tools.join(", ") : "(none)"));
    boxR.appendChild(kvRow("release_sha", (j.release_sha||"")));
    boxR.appendChild(kvRow("release_pkg", (j.release_pkg||src.release_pkg||"")));

    grid.appendChild(boxL);
    grid.appendChild(boxR);

    // buttons + raw json toggle
    const bar=el("div");
    bar.style.display="flex";
    bar.style.gap="10px";
    bar.style.marginTop="10px";

    const btn=(label)=> {
      const b=el("button",null,label);
      b.style.padding="6px 10px";
      b.style.borderRadius="10px";
      b.style.border="1px solid rgba(255,255,255,.12)";
      b.style.background="rgba(255,255,255,.04)";
      b.style.color="rgba(255,255,255,.9)";
      b.style.cursor="pointer";
      b.style.fontSize="12px";
      return b;
    };

    const bRefresh=btn("Refresh");
    const bJson=btn("View JSON");

    const pre=el("pre");
    pre.style.display="none";
    pre.style.marginTop="10px";
    pre.style.padding="10px";
    pre.style.borderRadius="12px";
    pre.style.border="1px solid rgba(255,255,255,.08)";
    pre.style.background="rgba(0,0,0,.25)";
    pre.style.maxHeight="280px";
    pre.style.overflow="auto";
    pre.style.fontSize="11px";
    pre.style.lineHeight="1.35";
    pre.textContent = payload.text || "";

    bRefresh.onclick = async () => {
      host.style.opacity=".8";
      try{
        const nxt = await fetchJson();
        render(host, nxt);
      }finally{
        host.style.opacity="1";
      }
    };
    bJson.onclick = () => {
      pre.style.display = (pre.style.display==="none") ? "block" : "none";
    };

    bar.appendChild(bRefresh);
    bar.appendChild(bJson);

    host.appendChild(head);
    host.appendChild(grid);
    host.appendChild(bar);
    host.appendChild(pre);
  }

  async function ensureMounted(){
    const host = findOrCreateHost();
    if(!host) return false;
    try{
      const payload = await fetchJson();
      render(host, payload);
      return true;
    }catch(e){
      host.innerHTML = '<div style="opacity:.85;font-size:12px">Ops panel failed to load</div>';
      return false;
    }
  }

  window.VSPOpsPanel = { ensureMounted };

  if(document.readyState==="loading"){
    document.addEventListener("DOMContentLoaded", ()=>ensureMounted());
  }else{
    ensureMounted();
  }
})();
"""
p.write_text(js, encoding="utf-8")
print("[OK] wrote", p)
PY

python3 -m py_compile wsgi_vsp_p910h.py 2>/dev/null || true
echo "[OK] js written"

sudo systemctl restart "$SVC"
bash bin/ops/ops_restart_wait_ui_v1.sh

echo "== verify ops_latest =="
curl -fsS "$BASE/api/vsp/ops_latest_v1" | python3 -c 'import sys,json;j=json.load(sys.stdin);print("ok=",j.get("ok"),"release_dir=", (j.get("source") or {}).get("release_dir"))'

echo "Open: $BASE/c/settings  (Ctrl+Shift+R)"
