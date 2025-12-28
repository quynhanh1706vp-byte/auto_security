#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="static/js/vsp_dashboard_luxe_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p69_${TS}"
echo "[OK] backup ${F}.bak_p69_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("static/js/vsp_dashboard_luxe_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

if "VSP_P67_MOUNT_ALIAS_GUARD_V1" not in s:
    print("[ERR] P67 marker not found; abort to avoid wrong patch.")
    raise SystemExit(2)

# 1) Ensure we have a native getElementById helper that will NOT be replaced
if "window.__VSP_NATIVE_GE" not in s:
    s = s.replace(
        "window.__VSP_GET = function(id){",
        "window.__VSP_NATIVE_GE = function(id){\n"
        "  try { return Document.prototype.getElementById.call(document, id); } catch(e){ return null; }\n"
        "};\n\n"
        "window.__VSP_GET = function(id){",
        1
    )

# 2) Fix the recursion: inside __VSP_GET, the first lookup MUST call __VSP_NATIVE_GE, not __VSP_GET
#    We handle let/var/const patterns.
s2 = re.sub(
    r'(\b(let|var|const)\s+el\s*=\s*)__VSP_GET\(\s*id\s*\)\s*;',
    r'\1window.__VSP_NATIVE_GE(id);',
    s,
    count=1
)

# If it didn't match, try a fallback simple replace (some builds may have slightly different spacing)
if s2 == s:
    s2 = s.replace("el = __VSP_GET(id);", "el = window.__VSP_NATIVE_GE(id);", 1)

s = s2

# 3) Add a tiny visible log so you KNOW luxe is executing
if "VSP_P69_EXEC_LOG_V1" not in s:
    s = s.replace(
        "/* VSP_P67_MOUNT_ALIAS_GUARD_V1",
        "console.info('[VSP] luxe boot marker (P69)');\n/* VSP_P67_MOUNT_ALIAS_GUARD_V1",
        1
    )
    s = s.replace("VSP_P67_MOUNT_ALIAS_GUARD_V1", "VSP_P67_MOUNT_ALIAS_GUARD_V1\n * VSP_P69_EXEC_LOG_V1", 1)

p.write_text(s, encoding="utf-8")
print("[OK] P69 applied: __VSP_GET now uses native getElementById (no recursion)")
PY

if command -v node >/dev/null 2>&1; then
  node -c "$F" >/dev/null 2>&1 && echo "[OK] node -c syntax OK" || { echo "[ERR] JS syntax fail"; exit 2; }
fi

echo "[DONE] P69 applied. Hard refresh: Ctrl+Shift+R"
