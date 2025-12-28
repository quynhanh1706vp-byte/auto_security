#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_v25_${TS}"
echo "[BACKUP] $F.bak_fix_v25_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Remove the broken V24 register block completely
txt2, n = re.subn(
    r'\n# === VSP_AFTER_REQUEST_REGISTER_V24 ===[\s\S]*?# === END VSP_AFTER_REQUEST_REGISTER_V24 ===\n',
    '\n',
    txt
)
if n:
    print("[OK] removed broken V24 block.")
txt = txt2

# 2) Remove any lingering '@app.after_request' decorators (safety)
txt, n2 = re.subn(r'^\s*@app\.after_request\s*\n', '', txt, flags=re.M)
if n2:
    print(f"[OK] removed {n2} stray decorator(s).")

# 3) Append a SAFE register block at EOF (runs after app is defined)
if "VSP_AFTER_REQUEST_REGISTER_V25" not in txt:
    reg = r'''
# === VSP_AFTER_REQUEST_REGISTER_V25 ===
def _vsp_register_after_request_v22_v25():
    try:
        g = globals()
        a = g.get("app")
        if a is None:
            return False
        if g.get("_VSP_AFTER_V22_REGISTERED"):
            return True
        if callable(getattr(a, "after_request", None)):
            a.after_request(vsp_after_request_persist_uireq_v22)
            g["_VSP_AFTER_V22_REGISTERED"] = True
            try:
                _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22_registered_v25 ts={_time.time()} file={__file__}")
            except Exception:
                pass
            return True
        return False
    except Exception as _e:
        try:
            _vsp_append_v22(_VSP_ERR_LOG_V22, f"after_v22_register_v25_fail err={repr(_e)} file={__file__}")
            _vsp_append_v22(_VSP_ERR_LOG_V22, _traceback.format_exc())
        except Exception:
            pass
        return False

_vsp_register_after_request_v22_v25()
# === END VSP_AFTER_REQUEST_REGISTER_V25 ===
'''.lstrip("\n")
    txt = txt.rstrip() + "\n\n" + reg + "\n"
    print("[OK] appended V25 register block at EOF.")
else:
    print("[OK] V25 block already present.")

p.write_text(txt, encoding="utf-8")
print("[DONE] vsp_demo_app.py fixed for syntax + safe register (V25).")
PY

python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile passed"
grep -n "VSP_AFTER_REQUEST_REGISTER_V25" "$F" | head -n 5 || true
