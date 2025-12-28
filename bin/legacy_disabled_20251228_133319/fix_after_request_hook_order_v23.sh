#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_afterreq_v23_${TS}"
echo "[BACKUP] $F.bak_fix_afterreq_v23_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# 1) Find V22 hook block
m = re.search(r'(# === VSP_AFTER_REQUEST_PERSIST_HOOK_V22 ===\s*\n)([\s\S]*?)(\n# === END VSP_AFTER_REQUEST_PERSIST_HOOK_V22 ===)', txt)
if not m:
    print("[ERR] cannot find V22 hook block markers in vsp_demo_app.py")
    raise SystemExit(2)

block = m.group(2)

# 2) Remove decorator line '@app.after_request' inside block (only if present)
block2 = re.sub(r'^\s*@app\.after_request\s*\n', '', block, flags=re.M)

if block2 == block:
    print("[INFO] decorator line not found (maybe already removed).")
else:
    print("[OK] removed @app.after_request decorator (V23).")

txt = txt[:m.start(2)] + block2 + txt[m.end(2):]

# 3) Ensure we register hook after app is defined
if "VSP_AFTER_REQUEST_REGISTER_V23" not in txt:
    reg_snip = r'''
# === VSP_AFTER_REQUEST_REGISTER_V23 ===
try:
    if not globals().get("_VSP_AFTER_V22_REGISTERED"):
        app.after_request(vsp_after_request_persist_uireq_v22)
        globals()["_VSP_AFTER_V22_REGISTERED"] = True
        try:
            _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22_registered ts={_time.time()} file={__file__}")
        except Exception:
            pass
except Exception as _e:
    try:
        _vsp_append_v22(_VSP_ERR_LOG_V22, f"after_v22_register_fail err={repr(_e)} file={__file__}")
    except Exception:
        pass
# === END VSP_AFTER_REQUEST_REGISTER_V23 ===
'''.lstrip("\n")

    m_app = re.search(r'^\s*app\s*=\s*Flask\s*\(.*\)\s*$', txt, flags=re.M)
    if not m_app:
        print("[ERR] cannot find 'app = Flask(...)' line to insert register snippet.")
        raise SystemExit(3)

    # insert right after that line
    lines = txt.splitlines(True)
    # locate line index
    pos = m_app.start()
    cur = 0
    idx = None
    for i, ln in enumerate(lines):
        if cur <= pos < cur + len(ln):
            idx = i
            break
        cur += len(ln)
    if idx is None:
        print("[ERR] internal locate error for app line.")
        raise SystemExit(4)

    lines.insert(idx+1, "\n" + reg_snip + "\n")
    txt = "".join(lines)
    print("[OK] inserted register snippet after app = Flask(...) (V23).")
else:
    print("[OK] V23 register snippet already present.")

p.write_text(txt, encoding="utf-8")
print("[DONE] vsp_demo_app.py updated (V23).")
PY

python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile passed"
grep -n "VSP_AFTER_REQUEST_REGISTER_V23" "$F" | head -n 5 || true
