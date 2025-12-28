#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_afterreq_v24_${TS}"
echo "[BACKUP] $F.bak_fix_afterreq_v24_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# 0) Ensure V22 hook function exists
if "def vsp_after_request_persist_uireq_v22" not in txt:
    print("[ERR] V22 hook function not found. You must have V22 inserted first.")
    raise SystemExit(2)

# 1) Remove any stray decorator lines to prevent import-time crash
txt2, n = re.subn(r'^\s*@app\.after_request\s*\n', '', txt, flags=re.M)
if n:
    print(f"[OK] removed {n} '@app.after_request' line(s).")
txt = txt2

# 2) Remove old failed/partial register blocks (if any)
txt = re.sub(r'\n# === VSP_AFTER_REQUEST_REGISTER_V23 ===[\s\S]*?# === END VSP_AFTER_REQUEST_REGISTER_V23 ===\n', '\n', txt)

if "VSP_AFTER_REQUEST_REGISTER_V24" in txt:
    print("[OK] already has V24 register block.")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

reg = r'''
# === VSP_AFTER_REQUEST_REGISTER_V24 ===
def _vsp_register_after_request_v22_v24():
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
                _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22_registered_v24 ts={_time.time()} file={__file__}")
            except Exception:
                pass
            return True
        return False
    except Exception as _e:
        try:
            _vsp_append_v22(_VSP_ERR_LOG_V22, f"after_v22_register_v24_fail err={repr(_e)} file={__file__}")
            _vsp_append_v22(_VSP_ERR_LOG_V22, _traceback.format_exc())
        except Exception:
            pass
        return False

# Try register immediately (works if app already exists by now)
_vsp_register_after_request_v22_v24()
# === END VSP_AFTER_REQUEST_REGISTER_V24 ===
'''.lstrip("\n")

# 3) Insert register block as LATE as possible but still top-level:
#    Prefer right AFTER the first line that defines global app
#    Accept many patterns:
#    - app = Flask(...)
#    - app=Flask(...)
#    - app = create_app(...)
#    - app=create_app(...)
pat_candidates = [
    r'^\s*app\s*=\s*Flask\s*\(.*$',
    r'^\s*app\s*=\s*create_app\s*\(.*$',
    r'^\s*app\s*=\s*get_app\s*\(.*$',
]

lines = txt.splitlines(True)
insert_at = None

for pat in pat_candidates:
    for i, ln in enumerate(lines):
        if re.match(pat, ln):
            insert_at = i+1
            break
    if insert_at is not None:
        break

if insert_at is None:
    # fallback: insert near bottom, before if __name__ == "__main__" if exists
    for i, ln in enumerate(lines):
        if re.match(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', ln):
            insert_at = i
            break

if insert_at is None:
    # last resort: append to end
    insert_at = len(lines)

lines.insert(insert_at, "\n" + reg + "\n")
txt = "".join(lines)

p.write_text(txt, encoding="utf-8")
print(f"[OK] inserted V24 register block at line ~{insert_at+1}")
PY

python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile passed"

echo "== sanity grep =="
grep -n "VSP_AFTER_REQUEST_REGISTER_V24" -n "$F" | head -n 5 || true
grep -n "app\s*=\s*Flask" -n "$F" | head -n 5 || true
