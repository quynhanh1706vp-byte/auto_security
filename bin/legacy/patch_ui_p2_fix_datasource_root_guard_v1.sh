#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_datasource_tab_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rootguard_${TS}"
echo "[BACKUP] $F.bak_rootguard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_datasource_tab_v1.js")
t = p.read_text(encoding="utf-8", errors="ignore")

if "// === VSP_P2_DATASOURCE_TABLE_V1 ===" not in t:
    print("[SKIP] P2 datasource block not found"); raise SystemExit(0)

# Replace ensureRoot() function inside the appended block (best-effort)
pattern = r"function ensureRoot\(\)\{[\s\S]*?\n  \}"
replacement = r"""function ensureRoot(){
    // Prefer CONTENT container ids (NOT tab buttons)
    let root =
         document.getElementById("vsp4-datasource")
      || document.getElementById("vsp-datasource-root")
      || document.getElementById("vsp-datasource-main")
      || document.querySelector("#vsp-tab-datasource-content")
      || document.querySelector("[data-tab-content='datasource']")
      || null;

    // Guard: never use a tab BUTTON/A as root
    if (root){
      const tn = (root.tagName || "").toUpperCase();
      const role = (root.getAttribute && root.getAttribute("role")) || "";
      if (tn === "A" || tn === "BUTTON" || role === "tab"){
        root = null;
      }
    }

    if (!root){
      root = document.createElement("div");
      root.id = "vsp-datasource-root";
      // attach inside a reasonable main content area if exists
      const host =
           document.querySelector("#vsp4-main")
        || document.querySelector("#vsp-main")
        || document.querySelector("#vsp-content")
        || document.body;
      host.appendChild(root);
    }
    if (!root.id) root.id = "vsp-datasource-root";
    return root;
  }"""

# only replace the FIRST ensureRoot() found AFTER the marker
idx = t.find("// === VSP_P2_DATASOURCE_TABLE_V1 ===")
head, tail = t[:idx], t[idx:]
tail2, n = re.subn(pattern, replacement, tail, count=1)
if n != 1:
    print("[WARN] ensureRoot() not patched (pattern mismatch). You may need manual edit.")
else:
    t = head + tail2
    p.write_text(t, encoding="utf-8")
    print("[OK] patched ensureRoot() with root-guard")

PY

# JS syntax check (commercial)
if command -v node >/dev/null 2>&1; then
  node --check static/js/vsp_datasource_tab_v1.js
  echo "[OK] node --check JS syntax OK"
else
  echo "[SKIP] node not found; skip JS syntax check"
fi

echo "[DONE] root guard applied. Hard refresh (Ctrl+Shift+R)."
