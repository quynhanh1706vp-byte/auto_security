#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runtime_error_overlay_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p77_${TS}"
echo "[OK] backup ${F}.bak_p77_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runtime_error_overlay_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
orig=s

if "VSP_P77_P64_DEBUG_ONLY_V1" in s:
    print("[OK] already patched P77")
    raise SystemExit(0)

# 1) Ensure the overlay root <div ...> has a stable id so we can hide it
idx = s.find("VSP Runtime Overlay")
if idx == -1:
    print("[ERR] cannot find 'VSP Runtime Overlay' marker in file")
    raise SystemExit(2)

# Find nearest opening <div ...> before the marker
start = s.rfind("<div", 0, idx)
if start == -1:
    print("[ERR] cannot find <div before marker")
    raise SystemExit(2)

end = s.find(">", start)
if end == -1:
    print("[ERR] cannot find end of opening div tag")
    raise SystemExit(2)

open_tag = s[start:end+1]
if "id=" not in open_tag:
    # Insert id into opening tag
    open_tag2 = open_tag[:-1] + ' id="vsp_overlay_p64_root" data-vsp-overlay="p64">'  # keep >
    s = s[:start] + open_tag2 + s[end+1:]
else:
    # still add data attr if missing (best effort)
    if "data-vsp-overlay" not in open_tag:
        open_tag2 = re.sub(r'>\s*$', ' data-vsp-overlay="p64">', open_tag)
        s = s[:start] + open_tag2 + s[end+1:]

# 2) Inject autohide logic (debug=1 shows; otherwise hide)
inject = r"""
/* VSP_P77_P64_DEBUG_ONLY_V1 */
(function(){
  try{
    var debug = false;
    try{ debug = /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }catch(e){}
    if (!debug){
      var el = document.getElementById("vsp_overlay_p64_root");
      if (el) el.style.display = "none";
    }
  }catch(e){}
})();
"""
# append at end
s = s.rstrip() + "\n\n" + inject + "\n"

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] patched overlay P64 => debug-only (default hidden)")
else:
    print("[WARN] no changes made (unexpected)")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax FAIL"; exit 2; }
fi

echo "[DONE] P77 applied. Reload normally: overlay hidden. Use ?debug=1 to show it."
