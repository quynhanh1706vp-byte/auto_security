#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_ops_v3_ultrasafe_${TS}"
echo "[BACKUP] $F.bak_ops_v3_ultrasafe_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, datetime, textwrap

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

start = "# === VSP_OPS_ROUTES_V3 ==="
end   = "# === END VSP_OPS_ROUTES_V3 ==="

pat = re.compile(rf"{re.escape(start)}[\s\S]*?{re.escape(end)}", re.M)
m = pat.search(txt)
if not m:
    raise SystemExit("[ERR] cannot find VSP_OPS_ROUTES_V3 block to replace")

block = textwrap.dedent(r"""
# === VSP_OPS_ROUTES_V3 ===
@app.get("/healthz")
def vsp_healthz_v3():
    # schema thương mại: ok + status + service
    return {"ok": True, "status": "OK", "service": "vsp-ui-8910"}

def _vsp_build_info_v3():
    # ultra-safe: không bao giờ throw
    try:
        import os, subprocess
        from datetime import datetime
        build_time = os.environ.get("VSP_BUILD_TIME") or datetime.utcnow().isoformat() + "Z"
        git_hash = os.environ.get("VSP_GIT_HASH") or "unknown"

        # chỉ thử git nếu thư mục có .git
        here = os.path.dirname(__file__)
        if git_hash == "unknown" and os.path.isdir(os.path.join(here, ".git")):
            try:
                git_hash = subprocess.check_output(
                    ["git", "rev-parse", "--short", "HEAD"],
                    cwd=here, stderr=subprocess.DEVNULL
                ).decode().strip() or "unknown"
            except Exception:
                git_hash = "unknown"

        return {
            "service": "VSP_UI_GATEWAY",
            "git_hash": git_hash,
            "build_time": build_time,
            "ts": datetime.utcnow().isoformat() + "Z",
            "python": "py" + __import__("sys").version.split()[0],
        }
    except Exception as e:
        # fallback tối đa
        return {
            "service": "VSP_UI_GATEWAY",
            "git_hash": "unknown",
            "build_time": "unknown",
            "ts": "unknown",
            "error": str(e),
        }

@app.get("/api/vsp/version")
def vsp_version_v3():
    # tuyệt đối không throw → không bao giờ rơi vào HTTP_500_INTERNAL wrapper
    info = _vsp_build_info_v3()
    return {"ok": True, "info": info}

# NOTE: giữ /api/vsp/dashboard_v3_latest làm deprecated alias (1 release), tránh hiểu nhầm schema
@app.get("/api/vsp/dashboard_v3_latest")
def vsp_dashboard_v3_latest_deprecated_v3():
    try:
        out = vsp_run_status_latest_v3()
        if isinstance(out, dict):
            out["deprecated"] = True
            out["deprecated_hint"] = "Use /api/vsp/run_status_latest"
        return out
    except Exception as e:
        return {"ok": False, "error": str(e), "deprecated": True}

@app.get("/api/vsp/run_status_latest")
def vsp_run_status_latest_v3():
    # Ưu tiên: nếu đã có hàm vsp_run_status_latest_v1() thì dùng lại
    try:
        fn = globals().get("vsp_run_status_latest_v1")
        if callable(fn):
            out = fn()
            if isinstance(out, dict):
                out.setdefault("ok", True)
            return out
        return {"ok": False, "error": "missing vsp_run_status_latest_v1()"}
    except Exception as e:
        return {"ok": False, "error": str(e)}
# === END VSP_OPS_ROUTES_V3 ===
""").strip()

txt2 = txt[:m.start()] + block + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced ops routes block with ultra-safe version")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
