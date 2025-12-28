#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

TS="$(date +%Y%m%d_%H%M%S)"
FILES=(
  "static/js/vsp_runs_kpi_compact_v3.js"
  "static/js/vsp_runs_quick_actions_v1.js"
  "static/js/vsp_runtime_error_overlay_v1.js"
)

python3 - <<'PY'
from pathlib import Path
import re, datetime, sys

marker = "VSP_P90_DOMREADY_BOOTFIX_V1"

helper = r"""
// VSP_P90_DOMREADY_BOOTFIX_V1
function __vsp_onReady(fn){
  try{
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn, { once:true });
    } else {
      fn();
    }
  } catch(e){
    console.error("[VSP_P90] onReady wrapper failed:", e);
  }
}
""".lstrip("\n")

def patch_one(p: Path):
    if not p.exists():
        return ("SKIP", f"{p} (missing)")
    s = p.read_text(encoding="utf-8", errors="replace")
    if marker in s:
        return ("OK", f"{p} (already patched)")

    orig = s

    # Insert helper near top (after "use strict" if present)
    if '"use strict"' in s or "'use strict'" in s:
        s = re.sub(r'(?m)^(["\']use strict["\'];\s*)$',
                   r'\1\n' + helper + "\n",
                   s, count=1)
    else:
        s = helper + "\n" + s

    changed = 0

    # Replace direct boot calls: boot();  fooBoot();  initSomething();  (top-level line)
    def repl(m):
        nonlocal changed
        fname = m.group(1)
        changed += 1
        return f"__vsp_onReady({fname});"

    s = re.sub(r'(?m)^\s*([A-Za-z_$][\w$]*(?:boot|Boot|init|Init)[\w$]*)\s*\(\s*\)\s*;\s*$',
               repl, s)

    # Also common pattern: window.addEventListener('load', boot);
    def repl2(m):
        nonlocal changed
        fname = m.group(1)
        changed += 1
        return f"window.addEventListener('load', () => __vsp_onReady({fname}), {{ once:true }});"
    s = re.sub(r'(?m)^\s*window\.addEventListener\(\s*["\']load["\']\s*,\s*([A-Za-z_$][\w$]*)\s*\)\s*;\s*$',
               repl2, s)

    # Fallback: if still no change but has function boot() defined, append safe auto-call
    if changed == 0:
        has_boot = re.search(r'(?m)^\s*function\s+boot\s*\(', s) or re.search(r'(?m)^\s*(?:const|let|var)\s+boot\s*=\s*\(', s)
        if has_boot:
            s += "\n\n// [VSP_P90] fallback autorun\n__vsp_onReady(() => { try { boot(); } catch(e){ console.error(e); } });\n"
            changed += 1

    if s == orig:
        return ("WARN", f"{p} (no effective change)")
    p.write_text(s, encoding="utf-8")
    return ("OK", f"{p} (patched, changes={changed})")

root = Path(".")
targets = [
    root/"static/js/vsp_runs_kpi_compact_v3.js",
    root/"static/js/vsp_runs_quick_actions_v1.js",
    root/"static/js/vsp_runtime_error_overlay_v1.js",
]

for t in targets:
    st, msg = patch_one(t)
    print(f"[{st}] {msg}")
PY

echo "== [P90] grep quick check =="
grep -RIn --line-number "VSP_P90_DOMREADY_BOOTFIX_V1|__vsp_onReady" static/js/vsp_runs_* static/js/vsp_runtime_error_overlay_v1.js 2>/dev/null | head -n 80 || true

echo "[OK] P90 done"
