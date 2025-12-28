#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p76_autorid_disable_${TS}.txt"
mkdir -p out_ci
echo "== [P76] scan + patch autorid_p63 ==" | tee "$OUT"

python3 - <<'PY'
from pathlib import Path
import re, datetime

root = Path("static/js")
files = sorted(root.glob("*.js"))

hit = []
for f in files:
    s = f.read_text(encoding="utf-8", errors="replace")
    if "_autorid_p63" in s:
        hit.append(f)

print(f"[INFO] files_with__autorid_p63={len(hit)}")
for f in hit:
    print(" -", f)

def ensure_debug_guard(s: str) -> str:
    if "__VSP_DEBUG_P76" in s:
        return s
    guard = r"""
/* __VSP_DEBUG_P76 */
var __VSP_DEBUG_P76 = (function(){
  try { return /(?:^|[?&])debug=1(?:&|$)/.test(String(location.search||"")); }
  catch(e){ return false; }
})();
"""
    if '"use strict"' in s:
        s = re.sub(r'("use strict"\s*;)', r'\1\n'+guard, s, count=1)
    else:
        s = guard + "\n" + s
    return s

patched = 0
for f in hit:
    s = f.read_text(encoding="utf-8", errors="replace")
    orig = s

    s = ensure_debug_guard(s)

    # 1) searchParams.set("_autorid_p63","1") => if(debug) set(...)
    s = re.sub(
        r'(\.searchParams\.set\(\s*[\'"]_autorid_p63[\'"]\s*,\s*[\'"]1[\'"]\s*\)\s*;)',
        r'if(__VSP_DEBUG_P76) \1',
        s
    )

    # 2) url += "&_autorid_p63=1";  => if(debug) url += ...
    s = re.sub(
        r'(\b[A-Za-z_$][A-Za-z0-9_$]*\b)\s*\+=\s*([\'"]&_autorid_p63=1[\'"])\s*;',
        r'if(__VSP_DEBUG_P76) \1 += \2;',
        s
    )

    # 3) any direct string literal occurrences in assignments: "...&_autorid_p63=1" => strip unless debug in code path
    # safer: just remove it from literals (autorid becomes opt-in via rules above)
    s = s.replace("&_autorid_p63=1", "")

    if s != orig:
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bak = f.with_name(f.name + f".bak_p76_{ts}")
        bak.write_text(orig, encoding="utf-8")
        f.write_text(s, encoding="utf-8")
        print(f"[OK] patched {f} (backup {bak.name})")
        patched += 1

print(f"[DONE] patched_files={patched}")
PY

echo "[DONE] P76 applied. Hard refresh: Ctrl+Shift+R" | tee -a "$OUT"
echo "[INFO] log: $OUT"
