#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"

patch_wrap_iife () {
  local F="$1"
  local TAG="$2"
  [ -f "$F" ] || { echo "[WARN] missing $F"; return 0; }
  cp -f "$F" "$F.bak_${TS}"
  python3 - <<PY
from pathlib import Path
p = Path("$F")
txt = p.read_text(encoding="utf-8", errors="ignore")
tag = "$TAG"
if tag in txt:
    print("[OK] already patched:", p)
    raise SystemExit(0)

wrapped = (
    f"// {tag}\\n"
    "(function(){\\n"
    "  try {\\n"
    "    if (window.__VSP_GUARD__ && window.__VSP_GUARD__[tag]) return;\\n"
    "    window.__VSP_GUARD__ = window.__VSP_GUARD__ || {};\\n"
    "    window.__VSP_GUARD__[tag] = true;\\n"
    "  } catch(e) {}\\n\\n"
    + txt +
    "\\n})();\\n"
)
p.write_text(wrapped, encoding="utf-8")
print("[OK] wrapped IIFE:", p)
PY
}

# 1) Fix SyntaxError effLimit already declared (wrap whole file into IIFE + guard)
patch_wrap_iife "static/js/vsp_runs_commercial_panel_v1.js" "VSP_WRAP_RUNS_COMMERCIAL_PANEL_V1"

# 2) Fix findChartsEngine not defined (inject fallback into dashboard enhance)
F_ENH="static/js/vsp_dashboard_enhance_v1.js"
if [ -f "$F_ENH" ]; then
  cp -f "$F_ENH" "$F_ENH.bak_${TS}"
  python3 - <<'PY'
import re
from pathlib import Path
p = Path("static/js/vsp_dashboard_enhance_v1.js")
txt = p.read_text(encoding="utf-8", errors="ignore")
TAG = "// === VSP_FIND_CHARTS_ENGINE_FALLBACK_V1 ==="
if TAG in txt:
    print("[OK] enhance already has fallback")
    raise SystemExit(0)

inject = r"""
// === VSP_FIND_CHARTS_ENGINE_FALLBACK_V1 ===
if (typeof window.findChartsEngine !== 'function') {
  window.findChartsEngine = function () {
    try {
      // Prefer explicit exported engines
      if (window.VSP_DASH_CHARTS_ENGINE) return window.VSP_DASH_CHARTS_ENGINE;
      if (window.VSP_DASH_CHARTS_V3) return window.VSP_DASH_CHARTS_V3;
      if (window.VSP_DASH_CHARTS_V2) return window.VSP_DASH_CHARTS_V2;

      // Heuristic: look for known globals from pretty charts scripts
      var cand = [
        window.vsp_dashboard_charts_v3,
        window.vsp_dashboard_charts_v2,
        window.VSP_CHARTS_V3,
        window.VSP_CHARTS_V2
      ].filter(Boolean)[0];

      return cand || null;
    } catch (e) { return null; }
  };
}
// === END VSP_FIND_CHARTS_ENGINE_FALLBACK_V1 ===
""".strip()+"\n"

# Insert after 'use strict' if present, else at top
m = re.search(r"(['\"])use strict\1\s*;?", txt)
if m:
    pos = m.end()
    txt = txt[:pos] + "\n" + inject + txt[pos:]
else:
    txt = inject + txt

p.write_text(txt, encoding="utf-8")
print("[OK] injected findChartsEngine fallback into:", p)
PY
else
  echo "[WARN] missing $F_ENH"
fi

# 3) Strengthen commercial cleanup: remove text nodes '\n \n' + hide conflicting CI Gate toast
F_CLEAN="static/js/vsp_ui_commercial_cleanup_v1.js"
if [ -f "$F_CLEAN" ]; then
  cp -f "$F_CLEAN" "$F_CLEAN.bak_${TS}"
  python3 - <<'PY'
import re
from pathlib import Path
p = Path("static/js/vsp_ui_commercial_cleanup_v1.js")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_UI_COMMERCIAL_CLEANUP_V1_TEXTNODE_TOAST_FIX"
if TAG in txt:
    print("[OK] cleanup already fixed")
    raise SystemExit(0)

patch = r"""
// === VSP_UI_COMMERCIAL_CLEANUP_V1_TEXTNODE_TOAST_FIX ===
function _vspRemoveStrayTextNodes() {
  try {
    function walk(node){
      if (!node) return;
      // remove stray text nodes like "\n \n"
      if (node.nodeType === Node.TEXT_NODE) {
        var t = (node.nodeValue || '').trim();
        if (t === '\\n' || t === '\\n\\n' || t === '\\n \\n' || t === '\\n \\n\\n' || t === '\\n\\n\\n') {
          node.parentNode && node.parentNode.removeChild(node);
          return;
        }
      }
      var kids = Array.from(node.childNodes || []);
      kids.forEach(walk);
    }
    walk(document.body);
  } catch(e){}
}

function _vspHideGateToast() {
  try {
    if (window.VSP_KEEP_GATE_TOAST) return;
    var els = Array.from(document.querySelectorAll('div,section,aside'));
    els.forEach(function(el){
      var t = (el.textContent || '').toUpperCase();
      // match both "-" and "–"
      if (t.includes('CI GATE') && t.includes('LATEST RUN')) {
        // hide only floating-ish blocks
        var st = window.getComputedStyle(el);
        if (st && (st.position === 'fixed' || st.position === 'sticky') && (st.right !== 'auto' || st.bottom !== 'auto')) {
          el.style.display = 'none';
          el.setAttribute('data-vsp-hidden-by', 'commercial_cleanup_v1');
        }
      }
    });
  } catch(e){}
}
// === END VSP_UI_COMMERCIAL_CLEANUP_V1_TEXTNODE_TOAST_FIX ===
""".strip()+"\n"

# Hook into existing run() or add a small runner at end
if "function run()" in txt:
    txt = re.sub(r"(function run\(\)\s*\{\s*)", r"\1\n    _vspRemoveStrayTextNodes();\n    _vspHideGateToast();\n", txt, count=1)
else:
    txt += "\n" + "function run(){ _vspRemoveStrayTextNodes(); _vspHideGateToast(); }\n"

# Also ensure it runs periodically (in case toast injects late)
txt += "\n" + patch + "\n" + """
try {
  var _n=0;
  var _iv=setInterval(function(){
    _vspRemoveStrayTextNodes();
    _vspHideGateToast();
    _n++; if (_n>40) clearInterval(_iv);
  }, 300);
} catch(e){}
"""
p.write_text(txt, encoding="utf-8")
print("[OK] updated cleanup shim:", p)
PY
else
  echo "[WARN] missing $F_CLEAN"
fi

echo "[DONE] UI fix bundle applied."
echo "Restart service:"
echo "  sudo systemctl restart vsp-ui-8910.service"
