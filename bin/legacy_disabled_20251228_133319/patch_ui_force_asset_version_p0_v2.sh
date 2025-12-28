#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FORCE_ASSET_VERSION_P0_V2"

TPL1="templates/vsp_dashboard_2025.html"
TPL2="templates/vsp_4tabs_commercial_v1.html"
JS="static/js/vsp_ui_global_shims_commercial_p0_v1.js"

for f in "$TPL1" "$TPL2" "$JS"; do
  [ -f "$f" ] || { echo "[ERR] missing $f"; exit 2; }
  cp -f "$f" "$f.bak_${MARK}_${TS}" && echo "[BACKUP] $f.bak_${MARK}_${TS}"
done

python3 - <<PY
from pathlib import Path
import re

ts = "$TS"
mark = "$MARK"

def ensure_asset_var(html: str) -> str:
    if "window.__VSP_ASSET_V" in html:
        return html
    return re.sub(r"</head>", f"<script>window.__VSP_ASSET_V='{ts}';</script>\\n</head>", html, flags=re.I)

def rewrite_js_urls(html: str) -> str:
    # rewrite ONLY /static/js/*.js (any existing ?v=...) to ?v=ts
    def repl(m):
        base = m.group(1)
        return f"{base}?v={ts}"
    return re.sub(r"(/static/js/[^\"'\\s>]+\\.js)(?:\\?v=[^\"'\\s>]*)?", repl, html)

def patch_tpl(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")
    s = ensure_asset_var(s)
    s = rewrite_js_urls(s)
    path.write_text(s, encoding="utf-8")
    print("[OK] patched tpl:", path)

def patch_shims(path: Path):
    s = path.read_text(encoding="utf-8", errors="replace")
    if mark in s:
        print("[OK] shims already patched")
        return

    shim = f"""
/* {mark}
 * Force cache-bust for dynamically injected /static/js/*.js scripts.
 */
(function(){{
  'use strict';
  if (window.__{mark}) return;
  window.__{mark}=1;

  function ver(){{
    return (window.__VSP_ASSET_V || window.VSP_ASSET_V || '{ts}');
  }}
  function rewrite(u){{
    try {{
      if(!u) return u;
      if(u.indexOf('/static/js/') === -1) return u;
      // remove any existing v= param
      u = u.replace(/[?&]v=[^&]+/g, '');
      u = u.replace(/[?&]$/, '');
      var sep = (u.indexOf('?') >= 0) ? '&' : '?';
      return u + sep + 'v=' + encodeURIComponent(ver());
    }} catch(_e) {{
      return u;
    }}
  }}

  var _append = Element.prototype.appendChild;
  Element.prototype.appendChild = function(node){{
    try {{
      if(node && node.tagName === 'SCRIPT' && node.src) node.src = rewrite(node.src);
    }} catch(_e) {{}}
    return _append.call(this, node);
  }};

  var _setAttr = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name, value){{
    try {{
      if(this && this.tagName === 'SCRIPT' && (name === 'src' || name === 'SRC') && typeof value === 'string') {{
        value = rewrite(value);
      }}
    }} catch(_e) {{}}
    return _setAttr.call(this, name, value);
  }};
}})();
"""
    path.write_text(shim.strip() + "\\n\\n" + s, encoding="utf-8")
    print("[OK] patched shims:", path)

patch_tpl(Path("templates/vsp_dashboard_2025.html"))
patch_tpl(Path("templates/vsp_4tabs_commercial_v1.html"))
patch_shims(Path("static/js/vsp_ui_global_shims_commercial_p0_v1.js"))
print("[OK] TS=", ts)
PY

node --check "$JS" >/dev/null && echo "[OK] node --check $JS"

echo "DONE. Now Ctrl+Shift+R. Verify all /static/js/*.js have ?v=$TS in Network."
