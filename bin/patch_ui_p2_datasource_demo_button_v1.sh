#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_demo_btn_${TS}"
echo "[BACKUP] $F.bak_demo_btn_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")
TAG="// === VSP_P2_DS_DEMO_BUTTON_V1 ==="
if TAG in t:
    print("[OK] demo button already present, skip"); raise SystemExit(0)

# inject helper + hook after renderTable(...)
hook = r"renderTable\(root, items\);\n"
ins = hook + r"""
    // === VSP_P2_DS_DEMO_BUTTON_V1 ===
    if ((total === 0) && Array.isArray(items)) {
      const st = qs("#vsp-ds-status", root);
      if (st && !qs("#vsp-ds-demo-btn", root)) {
        const btn = document.createElement("button");
        btn.id = "vsp-ds-demo-btn";
        btn.className = "vsp-btn vsp-btn-ghost";
        btn.textContent = "Load demo dataset";
        btn.style.marginLeft = "10px";
        btn.addEventListener("click", async function(){
          try{
            const r = await fetch("/static/sample/findings_demo.json", {cache:"no-store"});
            const demo = await r.json();
            setStatus(root, "<b>Demo</b>: loaded " + (demo.length||0) + " items");
            renderTable(root, demo);
          }catch(e){
            setStatus(root, "<span style='color:#fca5a5;'>Demo load failed</span>");
          }
        });
        st.appendChild(btn);
      }
    }
"""
t2, n = re.subn(hook, ins, t, count=1)
if n!=1:
    print("[ERR] cannot patch (renderTable hook not found)"); raise SystemExit(2)
p.write_text(t2, encoding="utf-8")
print("[OK] demo button injected")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check OK"
echo "[DONE] Demo button patch applied. Hard refresh Ctrl+Shift+R."
