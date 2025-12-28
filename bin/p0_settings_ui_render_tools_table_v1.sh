#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need node
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_bundle_tabs5_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p0_settingstbl_${TS}"
echo "[BACKUP] ${JS}.bak_p0_settingstbl_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_SETTINGS_RENDER_TOOLS_TABLE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r"""
/* VSP_P0_SETTINGS_RENDER_TOOLS_TABLE_V1
   Render a real tools table on /settings using /api/ui/settings_v2
*/
(function(){
  function el(tag, cls, html){
    var d=document.createElement(tag);
    if (cls) d.className=cls;
    if (html!=null) d.innerHTML=html;
    return d;
  }
  function cssOnce(){
    if (document.getElementById("vsp-settings-tools-style")) return;
    var st=el("style", null, `
      .vsp-tools-wrap{margin-top:12px;padding:14px;border-radius:16px;border:1px solid rgba(255,255,255,.08);background:rgba(255,255,255,.03)}
      .vsp-tools-h{display:flex;align-items:center;justify-content:space-between;gap:10px}
      .vsp-tools-title{font-weight:800;font-size:14px;opacity:.92}
      .vsp-tools-sub{font-size:12px;opacity:.75;margin-top:4px;line-height:1.35}
      .vsp-tools-meta{font-size:11px;opacity:.7}
      .vsp-tools-table{width:100%;border-collapse:separate;border-spacing:0;margin-top:10px;overflow:hidden;border-radius:14px}
      .vsp-tools-table th{font-size:11px;letter-spacing:.02em;text-transform:uppercase;opacity:.75;padding:10px 10px;background:rgba(0,0,0,.25);border-bottom:1px solid rgba(255,255,255,.08);text-align:left}
      .vsp-tools-table td{padding:10px 10px;border-bottom:1px solid rgba(255,255,255,.06);font-size:12px;opacity:.92}
      .vsp-pill{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;font-size:11px;border:1px solid rgba(255,255,255,.12);background:rgba(0,0,0,.18)}
      .vsp-dot{width:8px;height:8px;border-radius:50%;background:rgba(255,255,255,.35)}
      .vsp-dot.on{background:rgba(140,255,170,.9)}
      .vsp-dot.off{background:rgba(255,120,120,.9)}
      .vsp-mono{font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace}
      .vsp-right{margin-left:auto}
      .vsp-btn{cursor:pointer;border:1px solid rgba(255,255,255,.14);background:rgba(0,0,0,.2);color:inherit;padding:6px 10px;border-radius:12px;font-size:12px;opacity:.9}
      .vsp-btn:hover{opacity:1}
    `);
    st.id="vsp-settings-tools-style";
    document.head.appendChild(st);
  }

  async function getJSON(url){
    try{
      var r=await fetch(url,{credentials:"same-origin"});
      return await r.json();
    }catch(e){ return null; }
  }

  function pickSettingsMount(){
    // Try common containers: a main content div, or fallback to body
    return document.querySelector("#vsp-settings-main")
      || document.querySelector("#vsp-settings")
      || document.querySelector(".vsp-settings-main")
      || document.querySelector("main")
      || document.body;
  }

  function renderTable(mount, data){
    cssOnce();
    if (document.getElementById("vsp-tools-wrap")) return;

    var wrap=el("div","vsp-tools-wrap","");
    wrap.id="vsp-tools-wrap";

    var h=el("div","vsp-tools-h","");
    var left=el("div","", "");
    left.appendChild(el("div","vsp-tools-title","Tool Coverage & Policy"));
    var sub="Live data from <span class='vsp-mono'>/api/ui/settings_v2</span>.";
    if (data && data.ui && data.ui.kpi_mode) sub += " KPI mode: <span class='vsp-mono'>"+data.ui.kpi_mode+"</span>.";
    left.appendChild(el("div","vsp-tools-sub",sub));
    h.appendChild(left);

    var meta=el("div","vsp-tools-meta vsp-right","");
    var via = (data && (data.__via__ || data.notes || data.source)) ? (data.__via__ || data.notes || data.source) : "—";
    meta.innerHTML = "source: <span class='vsp-mono'>"+ String(via).slice(0,120) +"</span>";
    h.appendChild(meta);

    var btn=el("button","vsp-btn","Refresh");
    btn.onclick = async function(){
      var d = await getJSON("/api/ui/settings_v2");
      if (!d || !d.tools){ alert("settings_v2 unavailable"); return; }
      // simple refresh: remove + re-render
      try{ wrap.remove(); }catch(e){}
      renderTable(pickSettingsMount(), d);
    };
    h.appendChild(btn);

    wrap.appendChild(h);

    var tbl=el("table","vsp-tools-table","");
    var thead=el("thead","", "");
    thead.appendChild(el("tr","",
      "<th>Tool</th><th>Enabled</th><th>Timeout</th><th>Degrade</th><th>Notes</th>"
    ));
    tbl.appendChild(thead);

    var tb=el("tbody","", "");
    var tools = (data && data.tools) ? data.tools : {};
    var order = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"];
    order.forEach(function(tid){
      var t = tools[tid] || {};
      var en = !!t.enabled;
      var dot = "<span class='vsp-dot "+(en?"on":"off")+"'></span>";
      var pill = "<span class='vsp-pill'>"+dot+(en?"Enabled":"Disabled")+"</span>";
      var tout = (t.timeout_sec==null || t.timeout_sec==="") ? "—" : String(t.timeout_sec)+"s";
      var deg = (t.degrade_on_fail===false) ? "No" : "Yes";
      var notes = (t.notes||"").toString();
      var tr=el("tr","",
        "<td class='vsp-mono'>"+tid+"</td>"+
        "<td>"+pill+"</td>"+
        "<td class='vsp-mono'>"+tout+"</td>"+
        "<td>"+deg+"</td>"+
        "<td>"+(notes ? notes.replace(/[<>]/g,"") : "—")+"</td>"
      );
      tb.appendChild(tr);
    });
    tbl.appendChild(tb);
    wrap.appendChild(tbl);

    // insert near top of settings page
    mount.prepend(wrap);
  }

  async function init(){
    try{
      if (location.pathname !== "/settings") return;
      // wait for page JS to build layout
      for (var i=0;i<12;i++){
        await new Promise(r=>setTimeout(r,120));
        var mount = pickSettingsMount();
        if (mount) break;
      }
      var d = await getJSON("/api/ui/settings_v2");
      if (!d || !d.tools){
        var mount = pickSettingsMount();
        if (!mount) return;
        cssOnce();
        var warn=el("div","vsp-tools-wrap","<div class='vsp-tools-title'>Tool Coverage & Policy</div><div class='vsp-tools-sub'>settings_v2 unavailable. (degraded)</div>");
        warn.id="vsp-tools-wrap";
        mount.prepend(warn);
        return;
      }
      renderTable(pickSettingsMount(), d);
    }catch(e){}
  }

  if (document.readyState==="loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
"""
p.write_text(s + "\n\n" + textwrap.dedent(block).strip() + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

node --check "$JS"
echo "[OK] node --check passed"

# bump cache if available
if [ -x "bin/p1_set_asset_v_runtime_ts_v1.sh" ]; then
  bash bin/p1_set_asset_v_runtime_ts_v1.sh || true
fi

# restart
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
fi

echo "[OK] Open /settings: should see Tool Coverage & Policy table (live)."
