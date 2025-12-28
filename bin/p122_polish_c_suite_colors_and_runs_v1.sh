#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p122_${TS}"
echo "[OK] backup: ${F}.bak_p122_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_c_common_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P122_POLISH_C_SUITE_COLORS_AND_RUNS_V1"
if MARK in s:
    print("[OK] P122 already installed.")
    raise SystemExit(0)

addon = r"""
/* VSP_P122_POLISH_C_SUITE_COLORS_AND_RUNS_V1
 * - Make /c/* look consistent (dark pill buttons instead of blue links)
 * - Auto-style action links in Runs tab (Dashboard/CSV/Reports.tgz/Use RID...)
 */
(function(){
  try{
    var path = (location && location.pathname) ? String(location.pathname) : "";
    var page = "";
    if (path.startsWith("/c/")) {
      var seg = path.split("/").filter(Boolean);
      page = "c-" + (seg[1] || "dashboard");
    }
    // dataset markers for CSS targeting
    try{
      document.documentElement.dataset.vspSuite = "c";
      document.documentElement.dataset.vspPage = page;
      if (document.body){
        document.body.dataset.vspSuite = "c";
        document.body.dataset.vspPage = page;
      }
    }catch(_){}

    // inject CSS once
    var STYLE_ID="VSP_P122_STYLE";
    if (!document.getElementById(STYLE_ID)){
      var st=document.createElement("style");
      st.id=STYLE_ID;
      st.textContent = `
/* --- P122 C-suite theme polish --- */
[data-vsp-suite="c"] a{ color:rgba(210,225,255,.92); text-decoration:none; }
[data-vsp-suite="c"] a:hover{ text-decoration:underline; }

/* generic pill for action links (we add class in JS too) */
[data-vsp-suite="c"] a.vsp-btnlink{
  display:inline-block;
  padding:4px 10px;
  margin-right:6px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
  line-height:1.2;
}
[data-vsp-suite="c"] a.vsp-btnlink:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}

/* button polish (Use RID etc) */
[data-vsp-suite="c"] button.vsp-btn{
  padding:5px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  cursor:pointer;
}
[data-vsp-suite="c"] button.vsp-btn:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}
[data-vsp-suite="c"] button.vsp-btn.vsp-btn-mini{
  padding:4px 10px;
  font-size:12px;
}

/* Runs tab: treat table links like buttons even if no class */
[data-vsp-page="c-runs"] table a{
  display:inline-block;
  padding:4px 10px;
  margin-right:6px;
  border-radius:999px;
  background:rgba(255,255,255,.06);
  border:1px solid rgba(255,255,255,.14);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
  line-height:1.2;
}
[data-vsp-page="c-runs"] table a:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}

/* soften “link blue” in headers/toolstrips */
[data-vsp-suite="c"] .vsp-toolbar a,
[data-vsp-suite="c"] .toolbar a{
  display:inline-block;
  padding:4px 10px;
  border-radius:999px;
  background:rgba(255,255,255,.05);
  border:1px solid rgba(255,255,255,.12);
  color:rgba(235,242,255,.95);
  text-decoration:none !important;
  font-size:12px;
}
[data-vsp-suite="c"] .vsp-toolbar a:hover,
[data-vsp-suite="c"] .toolbar a:hover{
  background:rgba(255,255,255,.10);
  border-color:rgba(255,255,255,.22);
}
      `;
      document.head.appendChild(st);
    }

    // JS class helper: “button-hoá” một số link action phổ biến
    var WANT = {
      "dashboard":1, "csv":1, "reports.tgz":1, "reports":1, "html":1, "sarif":1, "summary":1, "open":1, "sha":1, "use rid":1
    };

    var _scheduled = false;
    function polish(){
      _scheduled = false;
      try{
        var as = document.querySelectorAll("a");
        for (var i=0;i<as.length;i++){
          var a=as[i];
          var t=(a.textContent||"").trim().toLowerCase();
          if (WANT[t]) a.classList.add("vsp-btnlink");
        }
        var bs = document.querySelectorAll("button");
        for (var j=0;j<bs.length;j++){
          var b=bs[j];
          var tb=(b.textContent||"").trim().toLowerCase();
          if (tb==="use rid" || tb==="refresh" || tb==="load" || tb==="save" || tb==="export"){
            b.classList.add("vsp-btn","vsp-btn-mini");
          }
        }
      }catch(_){}
    }
    function schedule(){
      if (_scheduled) return;
      _scheduled = true;
      (window.requestAnimationFrame||setTimeout)(polish, 16);
    }

    schedule();
    window.addEventListener("load", schedule, {once:true});
    try{
      new MutationObserver(schedule).observe(document.documentElement, {subtree:true, childList:true});
    }catch(_){}
  }catch(e){
    try{ console.warn("[P122] polish failed", e); }catch(_){}
  }
})();
"""
p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended P122 polish into", p)
PY

echo "[OK] P122 applied."
echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/runs"
echo "  http://127.0.0.1:8910/c/dashboard"
