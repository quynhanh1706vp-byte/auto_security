#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_dash_only_v1.js"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_force_render_v2_${TS}"
echo "[BACKUP] ${JS}.bak_force_render_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_dash_only_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# We patch inside the v1 block by replacing two exact lines we previously injected.
a = 'const toolsBox = $("#tools_box");'
b = 'const notes = $("#notes_box");'

if a not in s:
    print("[WARN] cannot find toolsBox line to patch; maybe file changed")
else:
    s = s.replace(a, r"""
    const ensureToolsBox = ()=>{
      let el = $("#tools_box")
        || document.querySelector("[data-vsp='tools_box']")
        || document.querySelector(".tools_box")
        || document.querySelector(".tool-lane")
        || null;

      if (!el){
        // find an anchor containing "Tool lane"
        const nodes = Array.from(document.querySelectorAll("div,section,header,h1,h2,h3,h4,span"));
        const anchor = nodes.find(n => (n.textContent||"").toLowerCase().includes("tool lane"));
        if (anchor){
          el = document.createElement("div");
          el.id = "tools_box";
          el.style.marginTop = "8px";
          // try append near anchor
          (anchor.parentElement || document.body).appendChild(el);
        }
      } else {
        if (!el.id) el.id = "tools_box";
      }
      return el;
    };
    const toolsBox = ensureToolsBox();
""".lstrip("\n"))

if b not in s:
    print("[WARN] cannot find notes line to patch; skip notes selector fix")
else:
    s = s.replace(b, r"""
    const ensureNotesBox = ()=>{
      let el = $("#notes_box") || document.querySelector("[data-vsp='notes_box']") || null;
      if (!el){
        const nodes = Array.from(document.querySelectorAll("div,section,header,h1,h2,h3,h4,span"));
        const anchor = nodes.find(n => (n.textContent||"").toLowerCase().strip().startswith("notes"));
        if (anchor){
          el = document.createElement("div");
          el.id = "notes_box";
          el.style.marginTop = "6px";
          (anchor.parentElement || document.body).appendChild(el);
        }
      } else {
        if (!el.id) el.id = "notes_box";
      }
      return el;
    };
    const notes = ensureNotesBox();
""".lstrip("\n"))

p.write_text(s, encoding="utf-8")
print("[OK] patched selectors in v1 force-render block")
PY

echo "== restart service (best effort) =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
fi

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R). Tool lane should stop showing UNKNOWN/[object Object]."
