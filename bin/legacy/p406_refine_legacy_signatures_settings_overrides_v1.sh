#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need node; need date

SET_JS="static/js/vsp_c_settings_v1.js"
OVR_JS="static/js/vsp_c_rule_overrides_v1.js"

[ -f "$SET_JS" ] || { echo "[ERR] missing $SET_JS"; exit 2; }
[ -f "$OVR_JS" ] || { echo "[ERR] missing $OVR_JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$SET_JS" "$SET_JS.bak_p406_${TS}"
cp -f "$OVR_JS" "$OVR_JS.bak_p406_${TS}"
echo "[OK] backups:"
echo " - $SET_JS.bak_p406_${TS}"
echo " - $OVR_JS.bak_p406_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

def patch_settings(p: Path):
    s = p.read_text(encoding="utf-8", errors="replace")
    # Find the legacy hiding function and expand needles/signatures safely.
    # We patch by inserting extra signatures into the existing arrays.
    # 1) add needles for legacy settings block that remains:
    #    "PIN default (stored local)" + buttons "Set AUTO" etc.
    if "PIN default (stored local)" in s and "Set PIN GLOBAL" in s and "Set USE RID" in s:
        # looks like legacy text is present in file; still we patch the hide matcher.
        pass

    # Inject extra needle strings into the code (robust to P405 content).
    # We'll add a block near the first occurrence of needles=[ ... ]
    pat = r'(needles\s*=\s*\[\s*)([^\]]*)\]'
    m = re.search(pat, s, flags=re.S)
    if not m:
        raise SystemExit("[ERR] cannot find needles=[...] in settings js (unexpected)")
    head = m.group(1)
    body = m.group(2)

    extra = r'''
      ,"PIN default (stored local)"
      ,"Set AUTO"
      ,"Set PIN GLOBAL"
      ,"Set USE RID"
      ,"Commercial behaviors"
    '''
    if "PIN default (stored local)" not in body:
        new_body = body.rstrip() + extra + "\n"
        s = s[:m.start(2)] + new_body + s[m.end(2):]

    # Also increase reaper duration a bit (from max=20 to max=40) if present.
    s = re.sub(r'const\s+max\s*=\s*20\s*;', 'const max=40; // 10s', s)

    p.write_text(s, encoding="utf-8")
    print("[OK] patched settings signatures + reaper duration")

def patch_overrides(p: Path):
    s = p.read_text(encoding="utf-8", errors="replace")

    # We add a direct killer for <pre> that contains VSP_RULE_OVERRIDES_EDITOR_P0_V1 (top legacy JSON block)
    if "VSP_RULE_OVERRIDES_EDITOR_P0_V1" in s and "legacy pre" in s:
        pass

    inject = r'''
      // hard-kill top legacy JSON block by exact signature inside PRE
      const preSig = 'VSP_RULE_OVERRIDES_EDITOR_P0_V1';
      for (const pre of Array.from(document.querySelectorAll("pre"))) {
        const t = (pre.innerText || "");
        if (!t.includes(preSig)) continue;
        let p = pre;
        for (let i=0; i<14 && p && p!==document.body; i++){
          const cls = (p.className||"").toString();
          const h = (p.getBoundingClientRect? p.getBoundingClientRect().height:0) || 0;
          if (cls.includes("card")||cls.includes("panel")||cls.includes("container")||h>=160) break;
          p = p.parentElement;
        }
        const target = p || pre;
        if (neverHide(target)) continue;
        target.classList.add("vsp_p405_hidden");
        target.setAttribute("data-vsp-legacy-hidden","1");
      }
'''

    # Insert this inject right after `function hideLegacyOnce(){`
    key = "function hideLegacyOnce(){"
    if key not in s:
        raise SystemExit("[ERR] cannot find hideLegacyOnce in overrides js (unexpected)")
    if "hard-kill top legacy JSON block by exact signature" not in s:
        s = s.replace(key, key + inject)

    # Extend reaper duration to 10s
    s = re.sub(r'const\s+max\s*=\s*20\s*;', 'const max=40; // 10s', s)

    p.write_text(s, encoding="utf-8")
    print("[OK] patched overrides: kill PRE signature + reaper duration")

patch_settings(Path("static/js/vsp_c_settings_v1.js"))
patch_overrides(Path("static/js/vsp_c_rule_overrides_v1.js"))
PY

echo "== [CHECK] node --check =="
node --check "$SET_JS"
node --check "$OVR_JS"

echo ""
echo "[OK] P406 installed."
echo "[NEXT] Hard refresh Ctrl+Shift+R:"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
