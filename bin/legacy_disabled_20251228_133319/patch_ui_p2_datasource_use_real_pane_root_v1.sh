#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_realroot_${TS}"
echo "[BACKUP] $F.bak_realroot_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_datasource_tab_v1.js")
t=p.read_text(encoding="utf-8", errors="ignore")

tag = "// === VSP_P2_DATASOURCE_TABLE_V1 ==="
i = t.find(tag)
if i < 0:
    print("[ERR] P2 datasource block not found (TAG missing)."); raise SystemExit(2)

head, tail = t[:i], t[i:]

# Replace ensureRoot() (best-effort) to always use the existing pane
pat = r"function ensureRoot\(\)\{[\s\S]*?\n  \}"
rep = r"""function ensureRoot(){
    // Prefer the real datasource pane rendered by template to avoid duplicate IDs
    let root =
         document.querySelector("#vsp-pane-datasource")
      || document.querySelector("section#vsp-pane-datasource")
      || document.querySelector("[data-tab='datasource']")
      || document.querySelector("[data-tab-content='datasource']")
      || document.getElementById("vsp4-datasource")
      || document.getElementById("vsp-datasource-root")
      || null;

    // Guard: if we accidentally matched a tab header/button/link, ignore it
    if (root){
      const tn = (root.tagName || "").toUpperCase();
      const role = (root.getAttribute && root.getAttribute("role")) || "";
      if (tn === "A" || tn === "BUTTON" || role === "tab") root = null;
    }

    if (!root){
      // Last resort: create ONE root under main container (avoid duplicates)
      root = document.createElement("div");
      root.id = "vsp-datasource-root";
      const host =
           document.querySelector("#vsp4-main")
        || document.querySelector("#vsp-content")
        || document.body;
      host.appendChild(root);
    }
    if (!root.id) root.id = "vsp-datasource-root";
    return root;
  }"""

tail2, n = re.subn(pat, rep, tail, count=1)
if n != 1:
    print("[ERR] cannot patch ensureRoot() (pattern mismatch)."); raise SystemExit(3)

p.write_text(head+tail2, encoding="utf-8")
print("[OK] ensureRoot() now prefers #vsp-pane-datasource")
PY

node --check static/js/vsp_datasource_tab_v1.js
echo "[OK] node --check OK"
echo "[DONE] apply, then Ctrl+Shift+R."
