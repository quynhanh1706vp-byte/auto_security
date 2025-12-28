#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_register_v26_${TS}"
echo "[BACKUP] $F.bak_register_v26_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# Remove any previous register blocks (V24/V25) if present
txt = re.sub(r'\n# === VSP_AFTER_REQUEST_REGISTER_V24 ===[\s\S]*?# === END VSP_AFTER_REQUEST_REGISTER_V24 ===\n', '\n', txt)
txt = re.sub(r'\n# === VSP_AFTER_REQUEST_REGISTER_V25 ===[\s\S]*?# === END VSP_AFTER_REQUEST_REGISTER_V25 ===\n', '\n', txt)

# Also remove any stray decorators (safety)
txt = re.sub(r'^\s*@app\.after_request\s*\n', '', txt, flags=re.M)

if "def vsp_after_request_persist_uireq_v22" not in txt:
    print("[ERR] V22 hook function not found. Ensure you have V22 inserted.")
    raise SystemExit(2)

if "VSP_AFTER_REQUEST_REGISTER_V26" in txt:
    print("[OK] V26 already present.")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

block = r'''
# === VSP_AFTER_REQUEST_REGISTER_V26 ===
try:
    if not globals().get("_VSP_AFTER_V22_REGISTERED"):
        app.after_request(vsp_after_request_persist_uireq_v22)
        globals()["_VSP_AFTER_V22_REGISTERED"] = True
        try:
            _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22_registered_v26 ts={_time.time()} file={__file__}")
        except Exception:
            pass
except Exception as _e:
    try:
        _vsp_append_v22(_VSP_ERR_LOG_V22, f"after_v22_register_v26_fail err={repr(_e)} file={__file__}")
        _vsp_append_v22(_VSP_ERR_LOG_V22, _traceback.format_exc())
    except Exception:
        pass
# === END VSP_AFTER_REQUEST_REGISTER_V26 ===
'''.lstrip("\n")

# Insert block BEFORE if __name__ == "__main__"
m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt, flags=re.M)
if m:
    ins = m.start()
    txt = txt[:ins] + block + "\n\n" + txt[ins:]
    print("[OK] inserted V26 register block before __main__.")
else:
    # Fallback: insert near end
    txt = txt.rstrip() + "\n\n" + block + "\n"
    print("[WARN] __main__ not found; appended V26 at EOF.")

p.write_text(txt, encoding="utf-8")
print("[DONE] vsp_demo_app.py updated (V26).")
PY

python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile passed"
grep -n "VSP_AFTER_REQUEST_REGISTER_V26" "$F" | head -n 5 || true
