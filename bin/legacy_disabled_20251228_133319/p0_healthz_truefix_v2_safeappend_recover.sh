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
cp -f "$APP" "${APP}.bak_broken_healthz_${TS}"
echo "[SNAPSHOT BROKEN] ${APP}.bak_broken_healthz_${TS}"

echo "== find latest compiling backup =="
BEST="$(python3 - <<'PY'
from pathlib import Path
import py_compile

baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for b in baks[:160]:
    try:
        tmp = Path("/tmp/_vsp_demo_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        print(b.as_posix())
        raise SystemExit(0)
    except Exception:
        continue
raise SystemExit(2)
PY
)" || { echo "[ERR] no compiling backup found"; exit 2; }

echo "[RESTORE] $BEST -> $APP"
cp -f "$BEST" "$APP"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove prior broken TRUEFIX V1 blocks if present
s = re.sub(
    r"\n# ===================== VSP_P0_HEALTHZ_TRUEFIX_V1 =====================.*?"
    r"# ===================== /VSP_P0_HEALTHZ_TRUEFIX_V1 =====================\n",
    "\n",
    s,
    flags=re.S,
)

# Remove any previously appended V2 blocks (idempotent)
s = re.sub(
    r"\n# ===================== VSP_P0_HEALTHZ_TRUEFIX_V2_SAFEAPPEND =====================.*?"
    r"# ===================== /VSP_P0_HEALTHZ_TRUEFIX_V2_SAFEAPPEND =====================\n",
    "\n",
    s,
    flags=re.S,
)

# Also disable decorator style if exists (avoid NameError in weird order)
s = re.sub(r'^\s*@app\.get\("/api/vsp/healthz"\)\s*$',
           '# [DISABLED] @app.get("/api/vsp/healthz")', s, flags=re.M)

block = r'''
# ===================== VSP_P0_HEALTHZ_TRUEFIX_V2_SAFEAPPEND =====================
# Register /api/vsp/healthz at EOF to avoid NameError or mid-statement injection.
import os, json, time
from pathlib import Path
from flask import jsonify

def _vsp_hz_read_release():
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

def _vsp_hz_release_status(relj):
    pkg = str(relj.get("release_pkg") or "").strip()
    if not pkg:
        return ("STALE", "", False)
    pp = Path(pkg) if pkg.startswith("/") else (Path("/home/test/Data/SECURITY_BUNDLE") / pkg)
    ok = pp.is_file() and pp.stat().st_size > 0
    return ("OK" if ok else "STALE", pkg, ok)

def _vsp_hz_pick_latest_rid():
    rid = os.environ.get("VSP_RID_LATEST", "").strip()
    if rid:
        return rid
    roots = [Path("/home/test/Data/SECURITY_BUNDLE/out_ci"), Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci")]
    best = None
    best_m = 0.0
    for root in roots:
        try:
            if not root.is_dir():
                continue
            for d in root.iterdir():
                if not d.is_dir():
                    continue
                f = d / "run_gate_summary.json"
                if f.is_file() and f.stat().st_size > 0:
                    mt = f.stat().st_mtime
                    if mt > best_m:
                        best_m = mt
                        best = d.name
        except Exception:
            continue
    # resolve "latest" symlink if any
    if best == "latest":
        for root in roots:
            lp = root / "latest"
            try:
                if lp.exists() and lp.is_symlink():
                    tgt = lp.resolve()
                    if tgt and tgt.name and tgt.name != "latest":
                        best = tgt.name
                        break
            except Exception:
                pass
    return best or ""

def _vsp_hz_degraded_tools_count(rid: str):
    if not rid:
        return 0
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

def _vsp_register_healthz_v2(app):
    if not app:
        return
    if getattr(app, "__vsp_healthz_truefix_v2", False):
        return
    # if rule already exists, don't re-add
    try:
        for r in app.url_map.iter_rules():
            if getattr(r, "rule", "") == "/api/vsp/healthz":
                app.__vsp_healthz_truefix_v2 = True
                return
    except Exception:
        pass

    def _handler():
        relj = _vsp_hz_read_release()
        rel_status, rel_pkg, rel_pkg_exists = _vsp_hz_release_status(relj)
        rid = _vsp_hz_pick_latest_rid()
        out = {
            "ok": True,
            "service_up": True,
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "rid_latest_gate_root": rid,
            "degraded_tools_count": _vsp_hz_degraded_tools_count(rid),
            "release_status": rel_status,
            "release_ts": relj.get("release_ts", ""),
            "release_sha": relj.get("release_sha", ""),
            "release_pkg": rel_pkg,
            "release_pkg_exists": rel_pkg_exists,
        }
        resp = jsonify(out)
        if out.get("release_ts"):  resp.headers["X-VSP-RELEASE-TS"] = str(out["release_ts"])
        if out.get("release_sha"): resp.headers["X-VSP-RELEASE-SHA"] = str(out["release_sha"])
        if out.get("release_pkg"): resp.headers["X-VSP-RELEASE-PKG"] = str(out["release_pkg"])
        resp.headers["X-VSP-HEALTHZ"] = "ok"
        return resp

    try:
        app.add_url_rule("/api/vsp/healthz", "vsp_healthz_truefix_v2", _handler, methods=["GET"])
    except Exception:
        # swallow any add_url_rule conflict
        pass
    app.__vsp_healthz_truefix_v2 = True

# register at EOF (safe)
try:
    _vsp_register_healthz_v2(globals().get("app") or globals().get("application"))
except Exception:
    pass
# ===================== /VSP_P0_HEALTHZ_TRUEFIX_V2_SAFEAPPEND =====================
'''

s = s.rstrip() + "\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended V2 SAFEAPPEND healthz block at EOF")
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] healthz truefix v2 safeappend applied."
