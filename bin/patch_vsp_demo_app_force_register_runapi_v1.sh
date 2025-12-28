#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$F" "$F.bak_force_runapi_${TS}"
echo "[BACKUP] $F.bak_force_runapi_${TS}"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore").replace("\r\n","\n").replace("\r","\n")

marker = "# === VSP_RUN_API_FORCE_REGISTER_V1 (do not edit) ==="
if marker in txt:
    print("[INFO] marker already present, skip")
else:
    # tìm điểm neo: sau khi tạo Flask app
    m = re.search(r"(?m)^\s*app\s*=\s*Flask\([^\n]*\)\s*$", txt)
    if not m:
        raise SystemExit("[ERR] cannot find line: app = Flask(...)")

    inject = r'''
# === VSP_RUN_API_FORCE_REGISTER_V1 (do not edit) ===
def _vsp__load_runapi_bp():
    try:
        # normal import (package-style)
        from run_api.vsp_run_api_v1 import bp_vsp_run_api_v1
        return bp_vsp_run_api_v1
    except Exception as e1:
        try:
            # fallback: load by file path (works even if run_api isn't a package)
            import importlib.util
            from pathlib import Path as _Path
            mod_path = _Path(__file__).resolve().parent / "run_api" / "vsp_run_api_v1.py"
            spec = importlib.util.spec_from_file_location("vsp_run_api_v1_dyn", str(mod_path))
            mod = importlib.util.module_from_spec(spec)
            assert spec and spec.loader
            spec.loader.exec_module(mod)
            return getattr(mod, "bp_vsp_run_api_v1", None)
        except Exception as e2:
            print("[VSP_RUN_API] WARN load failed:", repr(e1), repr(e2))
            return None

try:
    _bp = _vsp__load_runapi_bp()
    if _bp is not None:
        # dedupe by blueprint name
        if getattr(app, "blueprints", None) and _bp.name in app.blueprints:
            print("[VSP_RUN_API] already registered:", _bp.name)
        else:
            app.register_blueprint(_bp)
            print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")
    else:
        print("[VSP_RUN_API] WARN: bp_vsp_run_api_v1 is None")
except Exception as e:
    print("[VSP_RUN_API] WARN: cannot register run_api blueprint:", repr(e))
# === END VSP_RUN_API_FORCE_REGISTER_V1 ===
'''
    pos = m.end()
    txt2 = txt[:pos] + "\n" + inject + "\n" + txt[pos:]
    p.write_text(txt2, encoding="utf-8")
    print("[OK] injected run_api force register block after app = Flask(...)")

# compile check
import py_compile
py_compile.compile("vsp_demo_app.py", doraise=True)
print("[OK] py_compile OK")
PY
