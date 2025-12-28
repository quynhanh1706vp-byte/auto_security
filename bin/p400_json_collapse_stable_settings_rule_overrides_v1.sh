#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date; need ls; need grep

COMMON="static/js/vsp_c_common_v1.js"
[ -f "$COMMON" ] || { echo "[ERR] missing $COMMON"; exit 2; }

# Find tab scripts (names may vary)
SET_JS="$(ls -1 static/js/*settings* 2>/dev/null | head -n1 || true)"
OVR_JS="$(ls -1 static/js/*rule*over* 2>/dev/null | head -n1 || true)"

[ -n "${SET_JS:-}" ] || { echo "[ERR] cannot find settings js in static/js (pattern *settings*)"; exit 2; }
[ -n "${OVR_JS:-}" ] || { echo "[ERR] cannot find rule_overrides js in static/js (pattern *rule*over*)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$COMMON" "${COMMON}.bak_p400_${TS}"
cp -f "$SET_JS" "${SET_JS}.bak_p400_${TS}"
cp -f "$OVR_JS" "${OVR_JS}.bak_p400_${TS}"
echo "[OK] backups:"
echo "  - ${COMMON}.bak_p400_${TS}"
echo "  - ${SET_JS}.bak_p400_${TS}"
echo "  - ${OVR_JS}.bak_p400_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, datetime

common = Path("static/js/vsp_c_common_v1.js")
s = common.read_text(encoding="utf-8", errors="replace")

if "VSP_JSON_COLLAPSE_P400" not in s:
    block = r"""
/* ===================== VSP_JSON_COLLAPSE_P400 (stable) =====================
   Goal: collapse JSON <pre> reliably even when the tab re-renders.
   - Idempotent: marks processed nodes by data-vsp-json="1"
   - Safe: only touches <pre> that looks like JSON ({ or [)
============================================================================= */
(function(){
  try {
    window.VSPC = window.VSPC || {};
    if (window.VSPC.__jsonCollapseP400Installed) return;
    window.VSPC.__jsonCollapseP400Installed = true;

    function looksLikeJson(txt){
      if (!txt) return false;
      const t = (""+txt).trim();
      return t.startsWith("{") || t.startsWith("[");
    }

    function countLines(txt){
      if (!txt) return 0;
      // avoid any weird newline literal issues
      return (""+txt).split("\n").length;
    }

    function wrapPre(pre, opts){
      if (!pre || pre.dataset.vspJson === "1") return;
      const txt = pre.textContent || "";
      if (!looksLikeJson(txt)) return;

      const lines = countLines(txt);
      const page = (opts && opts.page) ? opts.page : "generic";
      const key  = (opts && opts.key) ? opts.key : ("vsp_json_expand::" + page);

      const wrapper = document.createElement("div");
      wrapper.className = "vsp-json-wrap";
      wrapper.style.cssText = "border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:10px;background:rgba(0,0,0,.18);";

      const hdr = document.createElement("div");
      hdr.className = "vsp-json-hdr";
      hdr.style.cssText = "display:flex;align-items:center;justify-content:space-between;margin-bottom:8px;gap:10px;";

      const title = document.createElement("div");
      title.textContent = `JSON (${lines} lines)`;
      title.style.cssText = "font-size:12px;opacity:.85;letter-spacing:.2px;";

      const btn = document.createElement("button");
      btn.type = "button";
      btn.textContent = "Expand";
      btn.style.cssText = "font-size:12px;padding:4px 10px;border-radius:999px;border:1px solid rgba(255,255,255,.14);background:rgba(255,255,255,.06);color:#e6edf3;cursor:pointer;";

      hdr.appendChild(title);
      hdr.appendChild(btn);

      // move pre into wrapper
      const parent = pre.parentNode
      if (!parent) return;

      wrapper.appendChild(hdr);
      parent.insertBefore(wrapper, pre);
      wrapper.appendChild(pre);

      pre.dataset.vspJson = "1";
      pre.style.margin = "0";
      pre.style.whiteSpace = "pre";
      pre.style.overflow = "auto";
      pre.style.maxHeight = "340px";

      function setExpanded(expanded){
        if (expanded){
          pre.style.display = "block";
          btn.textContent = "Collapse";
        } else {
          pre.style.display = "none";
          btn.textContent = "Expand";
        }
        try { localStorage.setItem(key, expanded ? "1" : "0"); } catch(e){}
      }

      // default collapsed unless previously expanded
      let expanded = False
      try { expanded = (localStorage.getItem(key) == "1"); } catch(e){ expanded = False; }
      setExpanded(expanded);

      btn.addEventListener("click", function(){
        const now = (pre.style.display === "none");
        setExpanded(now);
      });
    }

    window.VSPC.installJsonCollapseP400 = function(root, opts){
      try {
        root = root || document;
        const pres = root.querySelectorAll ? root.querySelectorAll("pre") : [];
        for (const pre of pres) wrapPre(pre, opts || {});
      } catch(e){}
    };

    window.VSPC.reapplyJsonCollapseP400 = function(page){
      // re-apply repeatedly for a short time; covers async renders without heavy observers.
      try {
        const key = "vsp_json_expand::" + (page || "generic");
        const opts = {page: page || "generic", key};
        let n = 0;
        const t = setInterval(function(){
          n++;
          try { window.VSPC.installJsonCollapseP400(document, opts); } catch(e){}
          if (n >= 40) clearInterval(t); // ~10s @250ms
        }, 250);
      } catch(e){}
    };

    console.log("[VSP] installed VSP_JSON_COLLAPSE_P400");
  } catch(e){}
})();
"""
    common.write_text(s + "\n" + block + "\n", encoding="utf-8")
    print("[OK] appended VSP_JSON_COLLAPSE_P400 into", common)
else:
    print("[OK] common already has VSP_JSON_COLLAPSE_P400")

PY

python3 - <<'PY'
from pathlib import Path

def patch_tab(path: Path, page_key: str):
    s = path.read_text(encoding="utf-8", errors="replace")
    if f"VSP_JSON_COLLAPSE_P400_TAB_{page_key}" in s:
        print("[OK] already patched", path)
        return
    block = f"""
/* === VSP_JSON_COLLAPSE_P400_TAB_{page_key} === */
(function(){{
  try {{
    if (!location || !location.pathname) return;
    if (location.pathname.indexOf("/c/{page_key}") !== 0) return;
    function go(){{
      try {{
        if (window.VSPC && typeof window.VSPC.reapplyJsonCollapseP400 === "function") {{
          window.VSPC.reapplyJsonCollapseP400("{page_key}");
        }} else if (window.VSPC && typeof window.VSPC.installJsonCollapseP400 === "function") {{
          window.VSPC.installJsonCollapseP400(document, {{page:"{page_key}", key:"vsp_json_expand::{page_key}"}});
        }}
      }} catch(e){{}}
    }}
    if (document.readyState === "loading") {{
      document.addEventListener("DOMContentLoaded", go);
    }} else {{
      go();
    }}
  }} catch(e){{}}
}})();
"""
    path.write_text(s + "\n" + block + "\n", encoding="utf-8")
    print("[OK] patched", path)

set_js = Path(r"""static/js/settings_render.js""")
ovr_js = Path(r"""static/js/vsp_c_rule_overrides_v1.js""")

patch_tab(set_js, "settings")
patch_tab(ovr_js, "rule_overrides")
PY
# placeholders replaced by bash below
