#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node

JS="static/js/vsp_data_source_lazy_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_contract_only_${TS}"
echo "[BACKUP] ${JS}.bak_contract_only_${TS}"

python3 - "$JS" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

# Replace the whole __vspPickArr function body with contract-only version.
pat = r'function\s+__vspPickArr\s*\(\s*j\s*\)\s*\{[\s\S]*?\n\}'
m = re.search(pat, s)
if not m:
    print("[ERR] cannot locate function __vspPickArr(j)"); raise SystemExit(2)

replacement = r'''function __vspPickArr(j){
  try{
    // Commercial contract: backend guarantees top-level "findings" is the source of truth.
    const a = j && Array.isArray(j.findings) ? j.findings : [];
    return a;
  }catch(e){
    return [];
  }
}'''
s = s[:m.start()] + replacement + s[m.end():]

# Update header comment marker (optional)
s = re.sub(r'/\*\s*VSP_[^*]*\s*\*/', '/* VSP_P1_DS_CONTRACT_ONLY_V1 */', s, count=1)

open(p,"w",encoding="utf-8").write(s)
print("[OK] patched __vspPickArr() to contract-only")
PY

node -c "$JS"
echo "[OK] node -c OK"
