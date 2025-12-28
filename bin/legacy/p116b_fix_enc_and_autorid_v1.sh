#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"

# 1) Patch enc() shim in vsp_fill_real_data* (the file shown in console)
python3 - <<'PY'
from pathlib import Path
import glob, re, datetime

cand = sorted(glob.glob("static/js/vsp_fill_real_data*tabs*p1*v1.js")) \
    or sorted(glob.glob("static/js/vsp_fill_real_data*.js"))

if not cand:
    print("[WARN] cannot find vsp_fill_real_data*.js under static/js")
    raise SystemExit(0)

f = Path(cand[0])
s = f.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P116B_ENC_SHIM"

if mark in s:
    print(f"[OK] enc shim already present: {f}")
    raise SystemExit(0)

bak = f.with_suffix(f.suffix + f".bak_p116b_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
print(f"[OK] backup: {bak}")

shim = (
    "\n// " + mark + "\n"
    "function enc(v){\n"
    "  try { return encodeURIComponent(v==null?'' : String(v)); }\n"
    "  catch(e){ return '' + (v==null?'' : v); }\n"
    "}\n"
)

# Insert after 'use strict' if exists, else at top
m = re.search(r'(^\\s*[\'"]use strict[\'"];\\s*$)', s, re.M)
if m:
    s2 = s[:m.end()] + shim + s[m.end():]
else:
    s2 = shim + s

f.write_text(s2, encoding="utf-8")
print(f"[OK] patched enc() shim into: {f}")
PY

# 2) Patch vsp_c_dashboard_v1.js to auto-redirect when rid is empty
python3 - <<'PY'
from pathlib import Path
import datetime, re

f = Path("static/js/vsp_c_dashboard_v1.js")
if not f.exists():
    print("[WARN] missing static/js/vsp_c_dashboard_v1.js")
    raise SystemExit(0)

s = f.read_text(encoding="utf-8", errors="replace")
mark = "VSP_P116B_AUTORID_REDIRECT"

if mark in s:
    print("[OK] autorid redirect already present")
    raise SystemExit(0)

bak = Path(str(f) + f".bak_p116b_{datetime.datetime.now().strftime('%Y%m%d_%H%M%S')}")
bak.write_text(s, encoding="utf-8")
print(f"[OK] backup: {bak}")

# Inject a tiny redirect right after detectRid() usage in main()
needle = r"const rid = detectRid\(\);"
if needle not in s:
    print("[WARN] cannot find 'const rid = detectRid();' to inject autorid")
    raise SystemExit(0)

inject = (
    needle + "\n"
    f"    // {mark}\n"
    "    if (!rid) {\n"
    "      try {\n"
    "        const last = localStorage.getItem('vsp_rid') || '';\n"
    "        if (last) {\n"
    "          const u = new URL(location.href);\n"
    "          u.searchParams.set('rid', last);\n"
    "          location.replace(u.toString());\n"
    "          return;\n"
    "        }\n"
    "      } catch(e) {}\n"
    "    }\n"
    "    // also expose rid for other modules\n"
    "    try { window.VSP_RID = rid || ''; } catch(e) {}\n"
)

s2 = s.replace(needle, inject, 1)
f.write_text(s2, encoding="utf-8")
print("[OK] patched autorid redirect + window.VSP_RID")
PY

echo
echo "[OK] P116b applied."
echo "[NEXT] Hard refresh browser (Ctrl+Shift+R) on: http://127.0.0.1:8910/c/dashboard?rid=VSP_CI_20251219_092640"
