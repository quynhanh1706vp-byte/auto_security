#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

F="static/js/vsp_c_common_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p133_${TS}"
echo "[OK] backup: ${F}.bak_p133_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_c_common_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P133_COLLAPSE_ALL_JSON_PRE_ON_SETTINGS_OVERRIDES_V1"
if MARK in s:
    print("[OK] already patched P133")
    raise SystemExit(0)

# safety: normalize common typos if any
s = s.replace(".startswith(", ".startsWith(").replace(".endswith(", ".endsWith(")

# 1) Try to adjust existing collapseHugePre threshold if that code exists:
# Replace: if (!looksJson || lines < 30) continue;
pat = re.compile(r'(?m)^(?P<indent>\s*)if\s*\(\s*!looksJson\s*\|\|\s*lines\s*<\s*\d+\s*\)\s*continue;\s*$')
m = pat.search(s)
if m:
    indent = m.group("indent")
    repl = (
        f"{indent}const isCSettingsOrOverrides = /(?:^|\\/)c\\/(settings|rule_overrides)(?:$)/"
        f".test(((location||{{}}).pathname)||\"\");\n"
        f"{indent}const minLines = isCSettingsOrOverrides ? 1 : 30;\n"
        f"{indent}if (!looksJson || lines < minLines) continue;"
    )
    s, n = pat.subn(repl, s, count=1)
    print(f"[OK] patched threshold line (count={n})")
else:
    print("[WARN] threshold line not found; will rely on appended runtime wrapper")

# 2) Append a runtime wrapper that ALWAYS collapses JSON <pre> on /c/settings and /c/rule_overrides
append = r"""
/* VSP_P133_COLLAPSE_ALL_JSON_PRE_ON_SETTINGS_OVERRIDES_V1 */
(function(){
  function _vsp_p133_isTarget(){
    try{
      const pn = ((location||{}).pathname)||"";
      return /(?:^|\/)c\/(settings|rule_overrides)(?:$)/.test(pn);
    }catch(_e){ return false; }
  }

  function _vsp_p133_wrapAllJsonPres(){
    if (!_vsp_p133_isTarget()) return;

    const pres = Array.from(document.querySelectorAll("pre"));
    for (const pre of pres){
      try{
        if (!pre || pre.nodeType !== 1) continue;
        if (pre.closest("details")) continue;

        const txt = (pre.textContent || "").trim();
        if (!txt) continue;

        const looksJson = (txt.startsWith("{") && txt.endsWith("}")) || (txt.startsWith("[") && txt.endsWith("]"));
        if (!looksJson) continue;

        const details = document.createElement("details");
        details.className = "vsp-details vsp-details--json";
        details.open = false;

        const sum = document.createElement("summary");
        sum.textContent = "Raw JSON (click to expand)";
        details.appendChild(sum);

        const parent = pre.parentNode;
        if (!parent) continue;
        parent.insertBefore(details, pre);
        details.appendChild(pre);

        pre.style.maxHeight = "360px";
        pre.style.overflow = "auto";
      }catch(_e){}
    }
  }

  function _vsp_p133_hook(){
    try{ _vsp_p133_wrapAllJsonPres(); }catch(_e){}
    try{
      const mo = new MutationObserver(function(){
        try{ _vsp_p133_wrapAllJsonPres(); }catch(_e){}
      });
      mo.observe(document.documentElement || document.body, {subtree:true, childList:true});
      console.log("[VSP] P133 installed (collapse all JSON <pre> on settings/rule_overrides)");
    }catch(_e){}
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", _vsp_p133_hook);
  else _vsp_p133_hook();
})();
"""
s = s.rstrip() + "\n\n" + append + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] appended P133 wrapper")
PY

if command -v node >/dev/null 2>&1; then
  echo "== [CHECK] node --check =="
  node --check "$F"
  echo "[OK] JS syntax OK"
else
  echo "[WARN] node not found; skipped syntax check"
fi

echo
echo "[NEXT] Hard refresh (Ctrl+Shift+R):"
echo "  http://127.0.0.1:8910/c/settings"
echo "  http://127.0.0.1:8910/c/rule_overrides"
