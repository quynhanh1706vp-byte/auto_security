#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "VSP_USE_RID_BTN_V1" "$F" && { echo "[OK] already patched Use RID"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_userid_${TS}"
echo "[BACKUP] $F.bak_userid_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

# 1) add mkUseRid right after mkLink
mklink_pat = re.compile(r'(function\s+mkLink\s*\([^\)]*\)\s*\{[\s\S]*?\}\n)', re.M)
if "function mkUseRid" not in s:
    m = mklink_pat.search(s)
    if not m:
        raise SystemExit("[ERR] cannot find function mkLink(...) block to insert mkUseRid")
    insert = m.group(1) + """
  // VSP_USE_RID_BTN_V1
  function mkUseRid(rid){
    return '<button class="vsp-btn vsp-btn-soft vsp-use-rid" data-rid="' + esc(rid) + '" title="Set current RID (for Export/Rules/Datasource)">Use RID</button>';
  }
"""
    s = s[:m.start(1)] + insert + s[m.end(1):]

# 2) include mkUseRid(rid) inside rowActions return array
# find return [ ... ].join(' ')
row_pat = re.compile(r'(function\s+rowActions\s*\(\s*rid\s*\)\s*\{[\s\S]*?return\s*\[\s*)([\s\S]*?)(\]\.join\(\s*[\'"]\s*[\'"]\s*\)\s*;\s*\}\s*)', re.M)
m = row_pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find function rowActions(rid) return array")
body = m.group(2)
if "mkUseRid" not in body:
    body = "      mkUseRid(rid),\n" + body
s = s[:m.start(2)] + body + s[m.end(2):]

# 3) add click handler once after 'pane.innerHTML = html;'
if "VSP_USE_RID_HANDLER_V1" not in s:
    pane_pat = re.compile(r'(pane\.innerHTML\s*=\s*html\s*;\s*\n)', re.M)
    m = pane_pat.search(s)
    if not m:
        raise SystemExit("[ERR] cannot find 'pane.innerHTML = html;' to attach handler")
    handler = m.group(1) + r"""
    // VSP_USE_RID_HANDLER_V1: event delegation for Use RID buttons
    pane.addEventListener('click', function(ev){
      var t = ev && ev.target ? ev.target : null;
      if(!t) return;
      var btn = (t.closest ? t.closest('.vsp-use-rid') : null);
      if(!btn) return;
      ev.preventDefault();

      var rid = btn.getAttribute('data-rid') || '';
      if(!rid) return;

      try {
        if (window.VSP_SET_RID) window.VSP_SET_RID(rid);
        try { localStorage.setItem("VSP_CURRENT_RID", rid); } catch(e){}
        var lab = document.getElementById("vsp-rid-label");
        if (lab) lab.textContent = "RID: " + rid;
        console.log("[VSP][RID] set from Runs:", rid);
      } catch(e){
        console.warn("[VSP][RID] set failed:", e);
      }
    }, { passive: false });
"""
    s = s[:m.start(1)] + handler + s[m.end(1):]

p.write_text(s, encoding="utf-8")
print("[OK] patched Use RID into runs tab js")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_wait_v1.sh
