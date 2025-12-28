#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dbg_marker_v2_${TS}"
echo "[BACKUP] ${F}.bak_dbg_marker_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_FIX_OVERALL_RUNS_V3_INLINE_PAYLOAD_V6"
if MARK not in s:
    print("[ERR] V6 marker not found")
    raise SystemExit(2)

start = s.find(MARK)
end = s.find("return __vsp__json(__vsp__payload)", start)
if end < 0:
    print("[ERR] cannot find V6 return line after marker")
    raise SystemExit(3)

chunk = s[start:end+len("return __vsp__json(__vsp__payload)")]

if "V6_DBG_MARKER_V2" in chunk:
    print("[SKIP] debug already injected")
    raise SystemExit(0)

# 1) inject dbg flag + probe near the beginning of the V6 block
chunk2 = chunk.replace(
    f"# {MARK}\n",
    f"# {MARK}\n"
    f"# V6_DBG_MARKER_V2\n"
    f"try:\n"
    f"    from flask import request as _req\n"
    f"    __dbg = str(_req.args.get('dbg','')).lower() in ('1','true','yes')\n"
    f"except Exception:\n"
    f"    __dbg = False\n"
    f"if __dbg:\n"
    f"    __vsp__payload['_patch_probe'] = 'V6_ACTIVE'\n",
    1
)

# 2) make the existing 'except: pass' inside V6 store error when dbg
# only patch inside this chunk to avoid touching other code
chunk3, n = re.subn(
    r"(?m)^\s*except Exception:\s*\n\s*pass\s*$",
    "except Exception as __e:\n"
    "    try:\n"
    "        if __dbg:\n"
    "            __vsp__payload['_overall_infer_err'] = repr(__e)\n"
    "    except Exception:\n"
    "        pass",
    chunk2,
    count=1
)
# If pattern not found, still proceed (maybe no except-pass now)
if n == 0:
    # add a generic note if dbg and nothing patched
    chunk3 = chunk2 + "\n# V6_DBG_MARKER_V2_NOTE: no except-pass to patch\n"

s2 = s[:start] + chunk3 + s[end+len("return __vsp__json(__vsp__payload)"):]
p.write_text(s2, encoding="utf-8")
print("[OK] injected dbg probe into V6 marker chunk")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restarted"
