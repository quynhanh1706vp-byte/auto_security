#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_dbg_overall_v6_${TS}"
echo "[BACKUP] ${F}.bak_dbg_overall_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_FIX_OVERALL_RUNS_V3_INLINE_PAYLOAD_V6"
if MARK not in s:
    print("[ERR] V6 marker not found")
    raise SystemExit(2)

# 1) Add a small dbg flag + probe at start of the V6 try block
# Find: "# V6 ...\ntry:\n"
s2, n1 = re.subn(
    rf"(?m)^(\s*)# {re.escape(MARK)}\s*\n\1try:\s*$",
    r"\1# " + MARK + r"\n\1try:\n\1    __dbg = False\n\1    try:\n\1        from flask import request as _req\n\1        __dbg = str(_req.args.get('dbg','')).lower() in ('1','true','yes')\n\1        if __dbg:\n\1            __vsp__payload['_patch_probe'] = 'V6_ACTIVE'\n\1    except Exception:\n\1        __dbg = False",
    s,
    count=1
)

if n1 == 0:
    print("[ERR] cannot locate V6 try block header to patch")
    raise SystemExit(3)

# 2) Replace "except Exception:\n    pass" at the end of V6 block to capture error when dbg=1
s3, n2 = re.subn(
    r"(?m)^\s*except Exception:\s*\n\s*pass\s*$",
    "except Exception as __e:\n"
    "    try:\n"
    "        # only expose error when ?dbg=1\n"
    "        if locals().get('__dbg'):\n"
    "            __vsp__payload['_overall_infer_err'] = repr(__e)\n"
    "    except Exception:\n"
    "        pass",
    s2,
    count=1
)

if n2 == 0:
    print("[WARN] cannot patch except-pass (pattern mismatch). Trying looser fallback...")
    s3, n2b = re.subn(
        r"(?ms)except Exception:\s*\n\s*pass\s*",
        "except Exception as __e:\n"
        "    try:\n"
        "        if locals().get('__dbg'):\n"
        "            __vsp__payload['_overall_infer_err'] = repr(__e)\n"
        "    except Exception:\n"
        "        pass\n",
        s2,
        count=1
    )
    if n2b == 0:
        print("[ERR] cannot patch except-pass at all")
        raise SystemExit(4)

p.write_text(s3, encoding="utf-8")
print("[OK] patched V6 debug hook")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"
sudo systemctl restart vsp-ui-8910.service || true
echo "[OK] restarted"
