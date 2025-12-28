#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "== PATCH DD GLOBAL ALL JS P0 V1 == TS=$TS"

# 0) quick inventory of files still referencing callsite
echo "== BEFORE hits =="
grep -RIn "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" static/js | head -n 40 || true

# 1) patch every js that still calls it directly
FILES="$(grep -RIl "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" static/js || true)"
for f in $FILES; do
  cp -f "$f" "$f.bak_dd_all_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")

# ensure helper exists in THIS file (in case file is loaded separately)
if "__VSP_DD_ART_CALL__(" not in s:
  helper = """
/* __VSP_DD_ART_CALL__ (P0): safe-call drilldown artifacts handler */
function __VSP_DD_ART_CALL__(h, ...args) {
  try {
    if (typeof h === 'function') return h(...args);
    if (h && typeof h.open === 'function') return h.open(...args);
    if (h && typeof h.install === 'function') return h.install(...args);
    if (h && typeof h.init === 'function') return h.init(...args);
  } catch(e) { try{ console.warn('[VSP][DD_SAFE_CALL]', e); }catch(_e){} }
  return null;
}
"""
  m=re.search(r"'use strict'\s*;", s)
  s = (s[:m.end()] + "\n" + helper + "\n" + s[m.end():]) if m else (helper + "\n" + s)

# wrap callsites: VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(...)
pat = re.compile(r"(?<!function\s)(?<![\w\.\$])VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", re.M)
s = pat.sub("__VSP_DD_ART_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2,", s)

# wrap window call too
pat2 = re.compile(r"(?<!function\s)(?<![\w\.\$])window\.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*\(", re.M)
s = pat2.sub("__VSP_DD_ART_CALL__(window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2,", s)

p.write_text(s, encoding="utf-8")
PY
  echo "[OK] patched calls in $f"
done

# 2) patch assignments to keep sync with window.* (tab scripts hay ghi đè local)
FILES2="$(grep -RIl "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\s*=" static/js || true)"
for f in $FILES2; do
  cp -f "$f" "$f.bak_dd_set_${TS}"
  python3 - <<PY
from pathlib import Path
import re
p=Path("$f")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace bare assignments (not var/let/const) to window.*
# e.g. "VSP_DASH... = dd;" -> "window.VSP_DASH... = dd;"
s = re.sub(r"(?m)^(?!\s*(?:var|let|const)\s+)\\s*VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2\\s*=",
           "window.VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2 =",
           s)

p.write_text(s, encoding="utf-8")
PY
  echo "[OK] patched setters in $f"
done

echo "== AFTER hits (should be empty) =="
grep -RIn "VSP_DASH_DRILLDOWN_ARTIFACTS_P1_V2(" static/js | head -n 40 || true

echo "== node checks (best-effort) =="
node --check static/js/vsp_bundle_commercial_v2.js || true

echo "== restart 8910 =="
bash /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_ui_8910_hardreset_p0_v1.sh

echo "[NEXT] Ctrl+Shift+R rồi chuyển tab qua lại. Console không được còn lỗi drilldown not-a-function."
