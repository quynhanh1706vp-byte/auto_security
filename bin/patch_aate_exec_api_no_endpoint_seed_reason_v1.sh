#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/TRDL_TEST_CENTER/v2

F="bin/aate_exec_4t_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_api_seed_${TS}"
echo "[BACKUP] $F.bak_api_seed_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("bin/aate_exec_4t_v1.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === AATE_EXEC_API_NO_ENDPOINT_SEED_REASON_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# In generate_api_suite(): after endpoints = extract_api_endpoints(...), if empty => mark special field
pat = r'def generate_api_suite\(run_dir: Path, base_url: str\):\n\s*endpoints = extract_api_endpoints\(run_dir, base_url\)\n\s*suite = \{"schema":"aate\.api_tests\.v1", "generated_at": now_iso\(\), "requests":\[\]\}\n'
m = re.search(pat, t)
if not m:
    print("[ERR] cannot locate generate_api_suite() header block")
    raise SystemExit(2)

ins = (
    'def generate_api_suite(run_dir: Path, base_url: str):\n'
    '    endpoints = extract_api_endpoints(run_dir, base_url)\n'
    '    suite = {"schema":"aate.api_tests.v1", "generated_at": now_iso(), "requests":[]}\n'
    '    if not endpoints:\n'
    '        suite["note"] = "NO_ENDPOINT_SEED"\n'
    '        return suite\n'
)

t = re.sub(pat, ins, t, count=1)

# In verdict_from_type(): if result_obj is None and type=API => NO_ENDPOINT_SEED
pat2 = r'return "SKIPPED", \[\{"type":type_name,"code":"EMPTY_SUITE","msg":"no checks/requests/scenarios generated \(base_url missing or no seeds\)"\}\]\n'
if re.search(pat2, t):
    rep2 = (
        'if type_name == "API":\n'
        '            return "SKIPPED", [{"type":"API","code":"NO_ENDPOINT_SEED","msg":"cannot extract API endpoints from api_catalog/net_summary; provide api_catalog.json or net_summary.requests[] urls"}]\n'
        '        return "SKIPPED", [{"type":type_name,"code":"EMPTY_SUITE","msg":"no checks/requests/scenarios generated (base_url missing or no seeds)"}]\n'
    )
    t = re.sub(pat2, rep2, t, count=1)

t += "\n" + TAG + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] patched exec: API NO_ENDPOINT_SEED")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
