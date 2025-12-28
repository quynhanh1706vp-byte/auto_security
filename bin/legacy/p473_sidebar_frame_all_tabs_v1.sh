#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p473_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 && HAS_NODE=1 || HAS_NODE=0
command -v sudo >/dev/null 2>&1 || true

SIDEBAR="static/js/vsp_c_sidebar_v1.js"
mkdir -p static/js

# 1) write shared sidebar+frame module
cp -f "$SIDEBAR" "$OUT/vsp_c_sidebar_v1.js.bak_${TS}" 2>/dev/null || true
cat > "$SIDEBAR" <<'JS'
/* VSP_P473_SIDEBAR_FRAME_ALL_TABS_V1 */
(function(){
  if (window.__VSP_SIDEBAR_FRAME_V1__) return;
  window.__VSP_SIDEBAR_FRAME_V1__ = 1;

  const W = 220;
  const LABELS = [
    ["Dashboard","/c/dashboard"],
    ["Runs & Reports","/c/runs"],
    ["Data Source","/c/data_source"],
    ["Settings","/c/settings"],
    ["Rule Overrides","/c/rule_overrides"],
  ];

  function ensureCss(){
    if (document.getElementById("vsp_p473_css")) return;
    const st = document.createElement("style");
    st.id = "vsp_p473_css";
    st.textContent = `
:root{--vsp_side_w:${W}px}
#vsp_side_menu_v1{position:fixed;top:0;left:0;bottom:0;width:var(--vsp_side_w);z-index:999999;
  background:rgba(10,14,22,0.98);border-right:1px solid rgba(255,255,255,0.08);
  padding:14px 12px;font-family:inherit}
#vsp_side_menu_v1 .vsp_brand{font-weight:800;letter-spacing:.3px;font-size:13px;margin:2px 0 12px 2px;opacity:.95}
#vsp_side_menu_v1 a{display:flex;align-items:center;gap:10px;text-decoration:none;
  color:rgba(255,255,255,0.84);padding:10px 10px;border-radius:12px;margin:6px 0;
  background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a:hover{background:rgba(255,255,255,0.06)}
#vsp_side_menu_v1 a.active{background:rgba(99,179,237,0.14);border-color:rgba(99,179,237,0.35);color:#fff}

/* shift whole app to the right */
html.vsp_p473_pad, body.vsp_p473_pad{padding-left:var(--vsp_side_w)}

/* "khung chuẩn" – đồng bộ spacing và max width cho mọi tab */
.vsp_p473_frame{
  max-width: 1440px;
  margin: 0 auto;
  padding: 16px 18px 26px;
}
`;
    document.head.appendChild(st);
  }

  function ensureMenu(){
    ensureCss();
    if (document.getElementById("vsp_side_menu_v1")) return;

    const menu = document.createElement("div");
    menu.id = "vsp_side_menu_v1";

    const brand = document.createElement("div");
    brand.className = "vsp_brand";
    brand.textContent = "VSP • Commercial";
    menu.appendChild(brand);

    const path = location.pathname || "";
    for (const [name, href] of LABELS){
      const a = document.createElement("a");
      a.href = href;
      a.textContent = name;
      if (path === href) a.classList.add("active");
      menu.appendChild(a);
    }
    document.body.appendChild(menu);

    document.documentElement.classList.add("vsp_p473_pad");
    document.body.classList.add("vsp_p473_pad");
  }

  function ensureFrame(){
    // chọn “root” của content để đóng khung (best-effort)
    const root =
      document.querySelector("#vsp_app") ||
      document.querySelector("#app") ||
      document.querySelector("#root") ||
      document.querySelector("main") ||
      document.querySelector(".container") ||
      document.body;

    // đừng đóng khung body trực tiếp nếu không cần
    if (root && root !== document.body) root.classList.add("vsp_p473_frame");
    else {
      // nếu không có root rõ ràng, bọc 1 div frame
      const existing = document.getElementById("vsp_p473_wrap");
      if (existing) return;
      const wrap = document.createElement("div");
      wrap.id = "vsp_p473_wrap";
      wrap.className = "vsp_p473_frame";
      while (document.body.firstChild) wrap.appendChild(document.body.firstChild);
      document.body.appendChild(wrap);
    }
  }

  function boot(){
    try{
      ensureMenu();
      ensureFrame();
      console && console.log && console.log("[P473] sidebar+frame ready");
    }catch(e){
      console && console.warn && console.warn("[P473] err", e);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", ()=>setTimeout(boot, 30));
  } else {
    setTimeout(boot, 30);
  }
})();
JS

echo "[OK] wrote $SIDEBAR" | tee -a "$OUT/log.txt"

# 2) append loader snippet to ALL vsp_c_* tab js files (so /c/* pages auto-load shared sidebar)
python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path("static/js")
cand = sorted([p for p in root.glob("vsp_c_*v*.js") if p.is_file()])
mark = "VSP_P473_LOADER_SNIPPET_V1"

loader = r"""

/* VSP_P473_LOADER_SNIPPET_V1 */
(function(){
  try{
    if (window.__VSP_SIDEBAR_FRAME_V1__) return; // already loaded
    if (document.getElementById("vsp_c_sidebar_v1_loader")) return;
    var s=document.createElement("script");
    s.id="vsp_c_sidebar_v1_loader";
    s.src="/static/js/vsp_c_sidebar_v1.js?v="+Date.now();
    document.head.appendChild(s);
  }catch(e){}
})();
"""

touched = 0
for p in cand:
    s = p.read_text(encoding="utf-8", errors="replace")
    if mark in s:
        continue
    # backup next to OUT handled by shell log; do minimal content patch here
    p.write_text(s + loader, encoding="utf-8")
    touched += 1

print(f"[OK] candidates={len(cand)} patched={touched}")
PY | tee -a "$OUT/log.txt"

# 3) syntax check (best-effort)
if [ "$HAS_NODE" = "1" ]; then
  echo "[INFO] node --check all touched vsp_c_*v*.js (best-effort)" | tee -a "$OUT/log.txt"
  for f in static/js/vsp_c_*v*.js; do
    node --check "$f" >/dev/null 2>&1 || { echo "[ERR] node check failed: $f" | tee -a "$OUT/log.txt"; exit 2; }
  done
fi

# 4) restart
echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] P473 done. Close ALL /c/* tabs, reopen (e.g. /c/dashboard) then Ctrl+Shift+R" | tee -a "$OUT/log.txt"
echo "[OK] log: $OUT/log.txt"
