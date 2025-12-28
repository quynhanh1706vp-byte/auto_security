#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dashboard_commercial_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2force_${TS}"
echo "[BACKUP] ${JS}.bak_p2force_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_dashboard_commercial_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_GLOBAL_RID_PICKER_FORCE_VISIBLE_V1C"
if MARK in s:
  print("[SKIP] already installed v1c")
  raise SystemExit(0)

addon = textwrap.dedent(r"""
/* ===================== __MARK__ ===================== */
(()=> {
  if (window.__vsp_p2_rid_picker_force_visible_v1c) return;
  window.__vsp_p2_rid_picker_force_visible_v1c = true;

  function ensureVisible(){
    try {
      // if original picker already exists, do nothing
      if (document.getElementById("vsp_rid_picker_v1b")) return;

      // try to call existing mount if exposed
      if (typeof window.__vsp_p2_global_rid_picker_v1b === "function") {
        try { window.__vsp_p2_global_rid_picker_v1b(); } catch(e) {}
      }
      if (document.getElementById("vsp_rid_picker_v1b")) return;

      // fallback: create a minimal fixed wrapper that triggers vsp:rid_changed
      const wrap = document.createElement("div");
      wrap.id = "vsp_rid_picker_v1b";
      wrap.style.cssText =
        "position:fixed;z-index:99997;top:10px;right:12px;" +
        "display:flex;align-items:center;gap:8px;" +
        "background:rgba(10,18,32,.82);border:1px solid rgba(255,255,255,.10);" +
        "backdrop-filter: blur(10px);padding:8px 10px;border-radius:12px;" +
        "font:12px/1.2 system-ui,Segoe UI,Roboto;color:#cfe3ff;box-shadow:0 10px 30px rgba(0,0,0,.35)";
      wrap.innerHTML = `
        <span style="opacity:.9;font-weight:700">RID</span>
        <input id="vsp_rid_manual_v1c" placeholder="paste RID…" style="width:220px;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.12);color:#d8ecff;border-radius:10px;padding:6px 10px;outline:none"/>
        <button id="vsp_rid_apply_v1c" style="padding:6px 10px;border-radius:10px;border:1px solid rgba(255,255,255,.12);background:rgba(30,60,110,.35);color:#d8ecff;cursor:pointer">Apply</button>
      `;
      document.body.appendChild(wrap);

      const inp = document.getElementById("vsp_rid_manual_v1c");
      const btn = document.getElementById("vsp_rid_apply_v1c");
      function dispatchRid(rid){
        try {
          const prev = window.__vsp_rid_latest || window.__vsp_rid_prev || null;
          window.__vsp_rid_prev = prev;
          window.__vsp_rid_latest = rid;
          window.dispatchEvent(new CustomEvent("vsp:rid_changed", {detail:{rid, prev}}));
        } catch(e) {}
      }
      btn.addEventListener("click", ()=> {
        const rid = (inp.value||"").trim();
        if (!rid) return;
        try { localStorage.setItem("vsp_follow_latest","off"); } catch(e) {}
        dispatchRid(rid);
      });
    } catch(e) {}
  }

  // after load, if picker not shown => force visible fallback
  setTimeout(ensureVisible, 1200);
})();
/* ===================== /__MARK__ ===================== */
""").replace("__MARK__", MARK)

p.write_text(s + "\n\n" + addon + "\n", encoding="utf-8")
print("[OK] appended v1c force visible fallback")
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check passed"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[DONE] P2 force visible v1c applied"
