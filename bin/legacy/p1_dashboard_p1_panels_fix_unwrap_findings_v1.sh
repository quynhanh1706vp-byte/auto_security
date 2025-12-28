#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3

JS="static/js/vsp_dashboard_gate_story_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_fix_unwrap_${TS}"
echo "[BACKUP] ${JS}.bak_fix_unwrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_dashboard_gate_story_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# Must be inside the addon section
if "VSP_P1_DASHBOARD_P1_PANELS_V1" not in s:
    raise SystemExit("[ERR] P1 panels addon not found in file")

# Replace the whole fetchJSON() function inside addon with a more robust version.
# Match the first occurrence of "async function fetchJSON(url){ ... }" AFTER the addon marker.
start = s.find("VSP_P1_DASHBOARD_P1_PANELS_V1")
if start < 0:
    raise SystemExit("[ERR] marker not found")

sub = s[start:]

m = re.search(r'\n\s*async\s+function\s+fetchJSON\s*\(\s*url\s*\)\s*\{.*?\n\s*\}\n', sub, flags=re.S)
if not m:
    raise SystemExit("[ERR] cannot find fetchJSON() inside addon section")

new_fetch = r'''
  function __vspP1_unwrapAny(x){
    // unwrap common wrappers and also auto-detect the {meta, findings[]} shape
    const seen = new Set();
    function isFindingsObj(o){
      return o && typeof o==="object" && !Array.isArray(o) &&
             o.meta && typeof o.meta==="object" &&
             Array.isArray(o.findings);
    }
    let cur = x;
    while (cur && typeof cur==="object" && !Array.isArray(cur) && !seen.has(cur)){
      seen.add(cur);
      if (isFindingsObj(cur)) return cur;

      // common wrapper keys
      const cand =
        cur.data ?? cur.json ?? cur.content ?? cur.payload ?? cur.body ?? cur.result ?? cur.obj ?? cur.file ?? cur.value;

      if (cand && cand !== cur){
        cur = cand;
        continue;
      }
      break;
    }

    // fallback: one-level deep scan for {meta, findings[]}
    if (cur && typeof cur==="object" && !Array.isArray(cur)){
      for (const k of Object.keys(cur)){
        const v = cur[k];
        if (isFindingsObj(v)) return v;
      }
    }
    return cur;
  }

  async function fetchJSON(url){
    const res = await fetch(url, {credentials:"same-origin"});
    const txt = await res.text();
    let j;
    try{
      j = JSON.parse(txt);
      // sometimes inner JSON is a string
      if (typeof j === "string" && (j.trim().startsWith("{") || j.trim().startsWith("["))){
        try{ j = JSON.parse(j); }catch(e){}
      }
    }catch(e){
      throw new Error("Non-JSON " + res.status);
    }
    if (!res.ok) throw new Error("HTTP " + res.status);

    // unwrap wrappers + auto-detect findings shape
    j = __vspP1_unwrapAny(j);
    return j;
  }
'''.strip("\n")

sub2 = sub[:m.start()] + "\n" + new_fetch + "\n" + sub[m.end():]
s2 = s[:start] + sub2

p.write_text(s2, encoding="utf-8")
print("[OK] replaced fetchJSON() in P1 addon with robust unwrap")
PY

echo "[DONE] unwrap fix applied."
echo "Next: restart UI then HARD refresh /vsp5."
