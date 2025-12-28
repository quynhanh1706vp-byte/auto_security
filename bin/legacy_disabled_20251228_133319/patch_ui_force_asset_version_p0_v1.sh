#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_FORCE_ASSET_VERSION_P0_V1"

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

ts="$TS"

def patch_tpl(path: Path):
  s=path.read_text(encoding="utf-8", errors="replace")
  # 1) define asset version early
  if "window.__VSP_ASSET_V" not in s:
    s=re.sub(r"</head>", f"<script>window.__VSP_ASSET_V='{ts}';</script>\\n</head>", s, flags=re.I)

  # 2) normalize all /static/js/*.js?v=... to v=TS (only in HTML tags)
  s=re.sub(r"(/static/js/[^\"'\\s>]+\\.js)(\\?v=[^\"'\\s>]*)?", lambda m: f"{m.group(1)}?v={ts}", s)

  path.write_text(s, encoding="utf-8")

def patch_global_shims(path: Path):
  s=path.read_text(encoding="utf-8", errors="replace")
  if "VSP_FORCE_ASSET_VERSION_P0_V1" in s:
    return
  shim=f"""
/* {MARK}
 * Force cache-bust for any dynamically injected /static/js/*.js script.
 */
(function(){{
  'use strict';
  if (window.__{MARK}) return;
  window.__{MARK}=1;

  function ver(){{
    return (window.__VSP_ASSET_V || window.VSP_ASSET_V || '{ts}');
  }}
  function rewrite(u){{
    try{{
      if(!u) return u;
      if(u.indexOf('/static/js/')===-1) return u;
      // drop existing v=
      u=u.replace(/([?&])v=[^&]+/g,'$1').replace(/[?&]$/,'');
      var sep = (u.indexOf('?')>=0) ? '&' : '?';
      return u + sep + 'v=' + encodeURIComponent(ver());
    }}catch(_e){{ return u; }}
  }}

  var _append = Element.prototype.appendChild;
  Element.prototype.appendChild = function(node){{
    try{{
      if(node && node.tagName==='SCRIPT' && node.src) node.src = rewrite(node.src);
    }}catch(_e){{}}
    return _append.call(this,node);
  }};

  var _setAttr = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function(name,value){{
    try{{
      if(this && this.tagName==='SCRIPT' && (name==='src'||name==='SRC') && typeof value==='string') {{
        value = rewrite(value);
      }}
    }}catch(_e){{}}
    return _setAttr.call(this,name,value);
  }};
}})();
"""
  s = shim.strip()+"\n\n"+s
  path.write_text(s, encoding="utf-8")

patch_tpl(Path("templates/vsp_dashboard_2025.html"))
patch_tpl(Path("templates/vsp_4tabs_commercial_v1.html"))
patch_global_shims(Path("static/js/vsp_ui_global_shims_commercial_p0_v1.js"))
print("[OK] patched templates + global shims, TS=", ts)
PY

node --check static/js/vsp_ui_global_shims_commercial_p0_v1.js
echo "DONE. Ctrl+Shift+R rồi mở lại /vsp4#dashboard. Check Network: mọi /static/js/*.js phải có v=$TS."
