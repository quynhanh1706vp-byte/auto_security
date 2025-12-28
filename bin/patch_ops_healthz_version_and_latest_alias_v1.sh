#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ops_healthz_version_${TS}"
echo "[BACKUP] $F.bak_ops_healthz_version_${TS}"

python3 - <<'PY'
import re, subprocess, os
from pathlib import Path
p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_OPS_HEALTHZ_VERSION_LATEST_ALIAS_V1 ==="
if TAG in txt:
    print("[OK] already patched"); raise SystemExit(0)

# chèn helper lấy git hash/build time
helper = f"""
{TAG}
import time, json
from datetime import datetime

def _vsp_build_info_v1():
    # build_time: lấy env nếu có (release build), fallback now
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
# === END VSP_OPS_HEALTHZ_VERSION_LATEST_ALIAS_V1 ===
"""

# cố gắng chèn sau import block đầu file
m = re.search(r"^(import[^\n]*\n)+", txt, flags=re.M)
if m:
    ins = m.end()
    txt = txt[:ins] + helper + txt[ins:]
else:
    txt = helper + "\n" + txt

# chèn routes: /healthz, /api/vsp/version
# tìm chỗ app = Flask(...)
m = re.search(r"\bapp\s*=\s*Flask\([^\)]*\)\s*\n", txt)
if not m:
    raise SystemExit("[ERR] cannot find Flask app init line")

# chèn route block sau khi app tạo xong
route_block = r"""
# === VSP_OPS_ROUTES_V1 ===
@app.get("/healthz")
def vsp_healthz_v1():
    return {"ok": True, "status": "OK"}

@app.get("/api/vsp/version")
def vsp_version_v1():
    return {"ok": True, "info": _vsp_build_info_v1()}

# Alias/deprecate: dashboard_v3_latest -> run_status_latest
# NOTE: giữ 1 release để backward compatible, UI thương mại chỉ dùng run_status_latest
@app.get("/api/vsp/dashboard_v3_latest")
def vsp_dashboard_v3_latest_deprecated_v1():
    try:
        data = vsp_run_status_latest_v1()
        if isinstance(data, dict):
            data["deprecated"] = True
            data["deprecated_hint"] = "Use /api/vsp/run_status_latest"
        return data
    except Exception as e:
        return {"ok": False, "deprecated": True, "error": str(e)}

@app.get("/api/vsp/run_status_latest")
def vsp_run_status_latest_v1():
    # TODO: bạn map vào logic latest progress hiện có
    # Nếu codebase đã có hàm lấy latest status/progress thì gọi vào đây.
    # Fallback an toàn: lấy RID mới nhất từ runs index resolved rồi trả run_status_v2/RID.
    try:
        import requests
        base = "http://127.0.0.1:8910"
        r = requests.get(base + "/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=1", timeout=5).json()
        rid = (r.get("items") or [{}])[0].get("run_id")
        if not rid:
            return {"ok": True, "status": "EMPTY", "rid": None}
        s = requests.get(base + f"/api/vsp/run_status_v2/{rid}", timeout=10).json()
        s["ok"] = True
        s["rid"] = rid
        return s
    except Exception as e:
        return {"ok": False, "error": str(e)}
# === END VSP_OPS_ROUTES_V1 ===
"""

# chèn route_block sau init app (ngay sau dòng app=Flask)
ins = m.end()
if "VSP_OPS_ROUTES_V1" not in txt:
    txt = txt[:ins] + route_block + txt[ins:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched ops routes: /healthz, /api/vsp/version, latest alias")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
