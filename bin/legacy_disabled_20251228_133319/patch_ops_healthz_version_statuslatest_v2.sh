#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ops_v2_${TS}"
echo "[BACKUP] $F.bak_ops_v2_${TS}"

python3 - <<'PY'
import re, subprocess, os
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_OPS_HEALTHZ_VERSION_STATUSLATEST_V2 ==="
if TAG in txt:
    print("[OK] already patched"); raise SystemExit(0)

# đảm bảo có import subprocess/os (nếu thiếu thì thêm rất an toàn)
need_imports = []
if "import subprocess" not in txt:
    need_imports.append("import subprocess")
if "import os" not in txt:
    need_imports.append("import os")
if need_imports:
    m = re.search(r"^(import[^\n]*\n)+", txt, flags=re.M)
    ins = m.end() if m else 0
    txt = txt[:ins] + "\n" + "\n".join(need_imports) + "\n" + txt[ins:]

block = f"""
{TAG}
from datetime import datetime

def _vsp_build_info_v2():
    build_time = os.environ.get("VSP_BUILD_TIME") or datetime.utcnow().isoformat() + "Z"
    git_hash = os.environ.get("VSP_GIT_HASH")
    if not git_hash:
        try:
            git_hash = subprocess.check_output(["git","rev-parse","--short","HEAD"], cwd=os.path.dirname(__file__)).decode().strip()
        except Exception:
            git_hash = "unknown"
    return {{
        "service": "VSP_UI_GATEWAY",
        "git_hash": git_hash,
        "build_time": build_time,
        "ts": datetime.utcnow().isoformat() + "Z"
    }}

# Healthz (schema thương mại: ok + status + service)
@app.get("/healthz")
def vsp_healthz_v2():
    return {{"ok": True, "status": "OK", "service": "vsp-ui-8910"}}

# Version endpoint (must-have)
@app.get("/api/vsp/version")
def vsp_version_v2():
    return {{"ok": True, "info": _vsp_build_info_v2()}}

# Alias run_status_latest (nếu hệ thống đã có hàm vsp_run_status_latest_v1 thì gọi lại)
@app.get("/api/vsp/run_status_latest")
def vsp_run_status_latest_alias_v2():
    try:
        fn = globals().get("vsp_run_status_latest_v1")
        if callable(fn):
            out = fn()
            if isinstance(out, dict):
                out.setdefault("ok", True)
            return out
        return {{"ok": False, "error": "missing vsp_run_status_latest_v1()"}}
    except Exception as e:
        return {{"ok": False, "error": str(e)}}
# === END VSP_OPS_HEALTHZ_VERSION_STATUSLATEST_V2 ===
"""

# append block vào cuối file (an toàn nhất, khỏi đụng structure)
txt = txt.rstrip() + "\n\n" + block + "\n"
p.write_text(txt, encoding="utf-8")
print("[OK] appended ops endpoints")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
