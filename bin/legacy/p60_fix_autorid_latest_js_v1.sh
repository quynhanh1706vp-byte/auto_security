#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p60_${TS}"
echo "[OK] backup ${F}.bak_p60_${TS}"

python3 - <<'PY'
from pathlib import Path
p = Path("static/js/vsp_tabs4_autorid_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="P60_AUTORID_LATEST_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

patch = r"""/* P60_AUTORID_LATEST_V1: ensure RID exists (no dashboard degrade) */
(function(){
  try{
    var u = new URL(location.href);
    var rid = u.searchParams.get("rid");
    if (rid && rid.trim()){
      try{ localStorage.setItem("vsp_rid", rid.trim()); }catch(_){}
      return;
    }
    try{
      var saved = localStorage.getItem("vsp_rid");
      if (saved && saved.trim()){
        u.searchParams.set("rid", saved.trim());
        location.replace(u.toString());
        return;
      }
    }catch(_){}

    // fetch latest rid from API
    fetch("/api/vsp/top_findings_v2?limit=1", {cache:"no-store"})
      .then(r => r.ok ? r.json() : null)
      .then(j => {
        var lrid = j && (j.rid || j.run_id); // tolerate older shape
        if (!lrid) return;
        try{ localStorage.setItem("vsp_rid", String(lrid)); }catch(_){}
        var uu = new URL(location.href);
        uu.searchParams.set("rid", String(lrid));
        location.replace(uu.toString());
      })
      .catch(_=>{});
  }catch(_){}
})();
"""

# prepend patch to be earliest
p.write_text(patch + "\n\n" + s, encoding="utf-8")
print("[OK] patched", p)
PY

echo "[DONE] P60 applied. Hard refresh browser: Ctrl+Shift+R"
