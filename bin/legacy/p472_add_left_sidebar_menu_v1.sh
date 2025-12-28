#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_c_common_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p472_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F" | tee -a "$OUT/log.txt"; exit 2; }

BK="${F}.bak_p472_${TS}"
cp -f "$F" "$BK"
echo "[OK] backup => $BK" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P472_SIDEBAR_MENU_V1"
if MARK in s:
    print("[OK] already patched P472")
else:
    add = r"""

/* VSP_P472_SIDEBAR_MENU_V1 */
(function(){
  const LABELS = [
    ["Dashboard","/c/dashboard"],
    ["Runs & Reports","/c/runs"],
    ["Data Source","/c/data_source"],
    ["Settings","/c/settings"],
    ["Rule Overrides","/c/rule_overrides"],
  ];
  function css(){
    return `
#vsp_side_menu_v1{position:fixed;top:0;left:0;bottom:0;width:220px;z-index:9999;
  background:rgba(10,14,22,0.98);border-right:1px solid rgba(255,255,255,0.08);
  padding:14px 12px;font-family:inherit}
#vsp_side_menu_v1 .vsp_brand{font-weight:700;letter-spacing:.3px;font-size:13px;margin:2px 0 12px 2px;opacity:.95}
#vsp_side_menu_v1 a{display:flex;align-items:center;gap:10px;text-decoration:none;
  color:rgba(255,255,255,0.82);padding:10px 10px;border-radius:12px;margin:6px 0;
  background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a:hover{background:rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a.active{background:rgba(99,179,237,0.14);border-color:rgba(99,179,237,0.35);color:#fff}
.vsp_p472_shift{margin-left:220px}
.vsp_p472_hide_tabbtn{display:none!important}
`;
  }
  function init(){
    try{
      if(document.getElementById("vsp_side_menu_v1")) return;
      const st=document.createElement("style");
      st.id="vsp_side_menu_v1_css";
      st.textContent=css();
      document.head.appendChild(st);

      const menu=document.createElement("div");
      menu.id="vsp_side_menu_v1";
      const brand=document.createElement("div");
      brand.className="vsp_brand";
      brand.textContent="VSP • Commercial";
      menu.appendChild(brand);

      const path=location.pathname || "";
      for(const [name,href] of LABELS){
        const a=document.createElement("a");
        a.href=href;
        a.textContent=name;
        if(path===href) a.classList.add("active");
        menu.appendChild(a);
      }
      document.body.appendChild(menu);

      // shift main content if possible
      const root = document.querySelector("#vsp_app") || document.querySelector("#app") || document.querySelector("main") || document.body;
      if(root && root!==document.body){
        root.classList.add("vsp_p472_shift");
      }else{
        document.body.classList.add("vsp_p472_shift");
      }

      // hide legacy tab buttons (only the 5 main ones)
      const wanted = new Set(LABELS.map(x=>x[0]));
      document.querySelectorAll("a,button").forEach(el=>{
        const t=(el.textContent||"").trim();
        if(wanted.has(t)) el.classList.add("vsp_p472_hide_tabbtn");
      });

      console && console.log && console.log("[P472] sidebar ready");
    }catch(e){
      console && console.warn && console.warn("[P472] sidebar init error", e);
    }
  }
  if(document.readyState==="loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
"""
    p.write_text(s + add, encoding="utf-8")
    print("[OK] patched P472 sidebar")
PY

if [ "$HAS_NODE" = "1" ]; then
  node --check "$F" && echo "[OK] node --check ok" | tee -a "$OUT/log.txt" || { echo "[ERR] node syntax check failed" | tee -a "$OUT/log.txt"; exit 2; }
fi

echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P472 done. Close ALL tabs, reopen /c/runs then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
