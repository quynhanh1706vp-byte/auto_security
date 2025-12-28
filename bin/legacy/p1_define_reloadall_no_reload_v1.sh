#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_data_source_charts_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_reloadall_${TS}"
echo "[BACKUP] ${JS}.bak_reloadall_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

js = Path("static/js/vsp_data_source_charts_v1.js")
s = js.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_DEFINE_RELOADALL_NO_RELOAD_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Heuristic: pick candidate functions that look like loaders
# We'll detect named functions referenced in code: load*, fetch*, render*
fn_names = set(re.findall(r'function\s+([A-Za-z_$][\w$]{2,})\s*\(', s))
# also arrow assignments: const loadX = async (...) => { ... }
fn_names |= set(re.findall(r'(?:const|let|var)\s+([A-Za-z_$][\w$]{2,})\s*=\s*(?:async\s*)?\(', s))
fn_names |= set(re.findall(r'(?:const|let|var)\s+([A-Za-z_$][\w$]{2,})\s*=\s*(?:async\s*)?\w+\s*=>', s))

cands = []
for name in sorted(fn_names):
    low = name.lower()
    if low.startswith(("load","fetch","render","refresh")):
        # exclude obvious tiny helpers
        if low in ("fetchjson","ensurebadge","setbadge"):
            continue
        cands.append(name)

# Keep top few to avoid calling wrong stuff
# Also allow a manual list by known patterns inside your file
picked = []
for name in cands:
    if any(k in name.lower() for k in ["chart","kpi","data","source","find","gate","run"]):
        picked.append(name)
# cap
picked = picked[:6]

# Build reloadAll that tries to call only existing functions safely
calls = "\n".join([f"      try{{ if(typeof window.{n}==='function') await window.{n}(); else if(typeof {n}==='function') await {n}(); }}catch(e){{}}" for n in picked])
if not calls:
    # fallback: try common global hooks if exist later
    calls = "      try{ if(typeof window.loadData==='function') await window.loadData(); }catch(e){}\n      try{ if(typeof window.refresh==='function') await window.refresh(); }catch(e){}"

addon = f"""
/* {MARK} */
(function(){{
  async function _vspReloadAllImpl(){{
    // Prefer calling in-page loaders to avoid full reload
{calls}
  }}

  window.VSP_reloadAll = async function(){{
    try{{ await _vspReloadAllImpl(); }}catch(e){{}}
  }};

  // also react to rid changed if any page uses current rid
  window.addEventListener("vsp:rid-changed", async (ev)=>{{
    try{{ await window.VSP_reloadAll(); }}catch(e){{}}
  }});
}})();
""".strip() + "\n"

js.write_text(s.rstrip()+"\n\n"+addon, encoding="utf-8")
print("[OK] patched reloadAll; picked =", picked)
PY
