#!/usr/bin/env bash
set -euo pipefail
H="run_api/vsp_watchdog_hook_v1.py"
[ -f "$H" ] || { echo "[ERR] missing $H"; exit 1; }

cp -f "$H" "$H.bak_enrich_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] $H.bak_enrich_*"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_watchdog_hook_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")

# In wrapped_run, after computing rid/target/profile/pid and before writing state,
# change behavior: if state exists (lazy-created), merge target/profile into it.
needle = "st = _default_state(rid, target, profile, pid)\n                _atomic_write(sp, st)\n"
if needle in s:
    s = s.replace(
        needle,
        "st = _default_state(rid, target, profile, pid)\n"
        "                # merge into existing state if it was lazy-created\n"
        "                if sp.exists():\n"
        "                    try:\n"
        "                        old = json.loads(sp.read_text(encoding='utf-8', errors='ignore'))\n"
        "                        old.update({k:v for k,v in st.items() if v not in (None,'')})\n"
        "                        st = old\n"
        "                    except Exception:\n"
        "                        pass\n"
        "                _atomic_write(sp, st)\n"
    )
else:
    print("[WARN] cannot find exact block; no changes applied")

p.write_text(s, encoding="utf-8")
print("[OK] patched enrich merge")
PY

python3 -m py_compile "$H"
echo "[OK] py_compile OK"
