#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_healthz_${TS}"
echo "[BACKUP] ${APP}.bak_healthz_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, json, time

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_HEALTHZ_V1"
if MARK in s:
    print("[OK] marker already present:", MARK)
    raise SystemExit(0)

# Find a safe insertion point: after app is created and before main
# We'll insert near other /api/vsp routes if possible, else before if __name__ == "__main__"
ins_at = None
m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
if m:
    ins_at = m.start()
else:
    ins_at = len(s)

block = r'''
# ===================== VSP_P0_HEALTHZ_V1 =====================
# Lightweight health endpoint for CI/demo readiness (no heavy IO; safe fallbacks)
import os, json, time
from pathlib import Path
from flask import jsonify, request

def _health_read_release():
    cands = []
    envp = os.environ.get("VSP_RELEASE_LATEST_JSON", "").strip()
    if envp:
        cands.append(envp)
    cands += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json",
        str(Path(__file__).resolve().parent / "out_ci" / "releases" / "release_latest.json"),
        str(Path(__file__).resolve().parent / "out" / "releases" / "release_latest.json"),
    ]
    for x in cands:
        try:
            rp = Path(x)
            if rp.is_file() and rp.stat().st_size > 0:
                return json.loads(rp.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            continue
    return {}

def _health_release_status(relj):
    pkg = str(relj.get("release_pkg") or "").strip()
    if not pkg:
        return ("STALE", "", False)
    # pkg is usually like out_ci/releases/xxx.tgz -> resolve under SECURITY_BUNDLE root if relative
    if pkg.startswith("/"):
        pp = Path(pkg)
    else:
        pp = Path("/home/test/Data/SECURITY_BUNDLE") / pkg
    ok = pp.is_file() and pp.stat().st_size > 0
    return ("OK" if ok else "STALE", pkg, ok)

def _health_rid_latest_gate_root():
    # Best effort: prefer env VSP_RID_LATEST if already set by UI, else empty.
    return os.environ.get("VSP_RID_LATEST", "").strip()

def _health_degraded_tools_count():
    # Best effort: read run_gate_summary.json for latest rid if possible, else 0
    rid = _health_rid_latest_gate_root()
    if not rid:
        return 0
    # common locations
    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE"),
    ]
    for r in roots:
        try:
            f = r / rid / "run_gate_summary.json"
            if f.is_file() and f.stat().st_size > 0:
                j = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                by = j.get("by_tool") or {}
                d = 0
                for _, v in by.items():
                    if isinstance(v, dict) and v.get("degraded") is True:
                        d += 1
                return d
        except Exception:
            continue
    return 0

@app.get("/api/vsp/healthz")
def vsp_healthz_v1():
    relj = _health_read_release()
    rel_status, rel_pkg, rel_pkg_exists = _health_release_status(relj)
    out = {
        "ok": True,
        "service_up": True,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "rid_latest_gate_root": _health_rid_latest_gate_root(),
        "degraded_tools_count": _health_degraded_tools_count(),
        "release_status": rel_status,
        "release_ts": relj.get("release_ts", ""),
        "release_sha": relj.get("release_sha", ""),
        "release_pkg": rel_pkg,
        "release_pkg_exists": rel_pkg_exists,
    }
    resp = jsonify(out)
    # also mirror in headers for super quick CLI grep
    if out.get("release_ts"):
        resp.headers["X-VSP-RELEASE-TS"] = str(out["release_ts"])
    if out.get("release_sha"):
        resp.headers["X-VSP-RELEASE-SHA"] = str(out["release_sha"])
    if out.get("release_pkg"):
        resp.headers["X-VSP-RELEASE-PKG"] = str(out["release_pkg"])
    resp.headers["X-VSP-HEALTHZ"] = "ok"
    return resp
# ===================== /VSP_P0_HEALTHZ_V1 =====================
'''

s2 = s[:ins_at] + "\n" + block + "\n" + s[ins_at:]
p.write_text(s2, encoding="utf-8")
print("[OK] inserted", MARK)
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart service =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] healthz installed."
