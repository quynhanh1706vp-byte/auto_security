#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_relid_fixattach_${TS}"
echo "[BACKUP] ${WSGI}.bak_relid_fixattach_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

mark = "VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1"
if mark not in s:
    raise SystemExit("[ERR] base marker not found; you must apply v1 first")

# Replace the old registration tail with a more robust attach logic
old_pat = r"""
# register hook safely \(no decorator; works for app/application exports\).*?
__vsp_app = globals\(\)\.get\("app"\) or globals\(\)\.get\("application"\)
if __vsp_app and hasattr\(__vsp_app, "after_request"\):
    if not getattr\(__vsp_app, "__vsp_p0_relid_afterreq_v1", False\):
        __vsp_app\.after_request\(__vsp_after_request\)
        __vsp_app\.__vsp_p0_relid_afterreq_v1 = True
"""

new_tail = r"""
# register hook robustly (try multiple candidates: globals + vsp_demo_app + wrapped .app)
def __vsp_try_attach(obj, label="obj"):
    try:
        if not obj or not hasattr(obj, "after_request"):
            return False
        if getattr(obj, "__vsp_p0_relid_afterreq_v1", False):
            return True
        obj.after_request(__vsp_after_request)
        obj.__vsp_p0_relid_afterreq_v1 = True
        return True
    except Exception:
        return False

_candidates = []

# 1) common globals
for _k in ("app","application","flask_app","vsp_app"):
    _o = globals().get(_k)
    if _o and _o not in _candidates:
        _candidates.append(_o)

# 2) if application is a wrapper exposing .app (common)
try:
    _wrap = globals().get("application")
    _inner = getattr(_wrap, "app", None)
    if _inner and _inner not in _candidates:
        _candidates.append(_inner)
except Exception:
    pass

# 3) import vsp_demo_app (UI flask app usually lives here)
try:
    import vsp_demo_app as _vda
    for _k in ("app","application"):
        _o = getattr(_vda, _k, None)
        if _o and _o not in _candidates:
            _candidates.append(_o)
except Exception:
    pass

_attached = False
for _idx, _o in enumerate(_candidates):
    if __vsp_try_attach(_o, f"cand{_idx}"):
        _attached = True

# Optional debug (set env VSP_RELID_DEBUG=1)
try:
    import os
    if os.environ.get("VSP_RELID_DEBUG","") == "1":
        print("[VSP_RELID] candidates=", len(_candidates), "attached=", _attached)
except Exception:
    pass
"""

# Find the exact tail inside the marker block and replace
m = re.search(old_pat, s, flags=re.S)
if not m:
    # fallback: replace from "# register hook safely" to end of marker block
    m2 = re.search(r"# register hook safely.*?(?=\n# ===================== /VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1)", s, flags=re.S)
    if not m2:
        raise SystemExit("[ERR] cannot locate old registration tail to replace")
    s = s[:m2.start()] + new_tail.strip("\n") + "\n" + s[m2.end():]
else:
    s = s[:m.start()] + new_tail.strip("\n") + "\n" + s[m.end():]

p.write_text(s, encoding="utf-8")
print("[OK] patched attach logic for", mark)
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] v2 fixattach applied."
