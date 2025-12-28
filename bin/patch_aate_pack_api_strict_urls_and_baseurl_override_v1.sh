#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/TRDL_TEST_CENTER/v2

F="bin/aate_pack_run_v2.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_api_strict_${TS}"
echo "[BACKUP] $F.bak_api_strict_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("bin/aate_pack_run_v2.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === AATE_PACK_API_STRICT_URLS_AND_BASEURL_OVERRIDE_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# 1) Ensure base_url can be overridden by env AATE_BASE_URL_OVERRIDE
# Find base_url assignment in main()
t = re.sub(
    r'(base_url\s*=\s*manifest\.get\("base_url"\)[^\n]*\n)',
    r'\1    envb = os.environ.get("AATE_BASE_URL_OVERRIDE","").strip()\n'
    r'    if envb.startswith("http"):\n'
    r'        base_url = envb\n',
    t,
    count=1
)

# 2) Make API endpoint counting STRICT: count only URLs from known shapes; if unknown => endpoints_total=0
# Replace in api_ready() the fallback count_json_entries(obj) block.
pat = r'else:\n\s*endpoints_total\s*=\s*count_json_entries\(obj\)\n\s*src\s*=\s*str\(net_sum\)\n'
rep = (
    'else:\n'
    '            # unknown / unparseable shape => do NOT assume endpoints exist\n'
    '            endpoints_total = 0\n'
    '            src = str(net_sum)\n'
    '            soft.append({"type":"API","code":"NET_SUMMARY_UNPARSEABLE","msg":"net_summary/api_calls exists but cannot extract URLs; treat endpoints_total=0"})\n'
)
t2, n = re.subn(pat, rep, t, count=1)
t = t2

# 3) Also, when api_catalog is unknown shape, do not count dict keys
pat2 = r'else:\n\s*endpoints_total\s*=\s*count_json_entries\(obj\)\n\s*src\s*=\s*str\(api_catalog\)\n'
rep2 = (
    'else:\n'
    '            endpoints_total = 0\n'
    '            src = str(api_catalog)\n'
    '            soft.append({"type":"API","code":"API_CATALOG_UNPARSEABLE","msg":"api_catalog exists but cannot extract URLs; treat endpoints_total=0"})\n'
)
t = re.sub(pat2, rep2, t, count=1)

# append tag
t += "\n" + TAG + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] patched packer: base_url override + strict API URL extraction")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
