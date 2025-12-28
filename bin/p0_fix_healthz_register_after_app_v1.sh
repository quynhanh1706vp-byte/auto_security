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
cp -f "$APP" "${APP}.bak_healthz_truefix_${TS}"
echo "[BACKUP] ${APP}.bak_healthz_truefix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# If a broken decorator-based healthz exists, neutralize it by rewriting "@app.get(...)" to a comment marker
s = re.sub(r'^\s*@app\.get\("/api/vsp/healthz"\)\s*$', '# [DISABLED_BY_TRUEFIX] @app.get("/api/vsp/healthz")', s, flags=re.M)

MARK = "VSP_P0_HEALTHZ_TRUEFIX_V1"
if MARK in s:
    print("[OK] already applied:", MARK)
    p.write_text(s, encoding="utf-8")
    raise SystemExit(0)

# Insert a register function near imports (top of file after Flask import if possible)
ins_top = None
m_flask = re.search(r'^(from flask import .*)$', s, flags=re.M)
if m_flask:
    ins_top = m_flask.end()
else:
    ins_top = 0

block = r'''
# ===================== VSP_P0_HEALTHZ_TRUEFIX_V1 =====================
# Healthz is registered AFTER app exists (avoid NameError if code is reordered)
import os, json, time
from pathlib import Path
from flask import jsonify

def _vsp_health_read_release():
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

def _vsp_health_release_status(relj):
    pkg = str(relj.get("release_pkg") or "").strip()
    if not pkg:
        return ("STALE", "", False)
    pp = Path(pkg) if pkg.startswith("/") else (Path("/home/test/Data/SECURITY_BUNDLE") / pkg)
    ok = pp.is_file() and pp.stat().st_size > 0
    return ("OK" if ok else "STALE", pkg, ok)

def _vsp_health_pick_latest_rid():
    rid = os.environ.get("VSP_RID_LATEST", "").strip()
    if rid:
        return rid

    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]
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

    # resolve "latest" alias if present
    if best == "latest":
        for root in roots:
            lp = root / "latest"
            if not lp.exists():
                continue
            try:
                if lp.is_symlink():
                    tgt = lp.resolve()
                    if tgt and tgt.name and tgt.name != "latest":
                        best = tgt.name
                        break
            except Exception:
                pass
    return best or ""

def _vsp_health_degraded_tools_count(rid: str):
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

def _vsp_register_healthz(app):
    if getattr(app, "__vsp_healthz_truefix_v1", False):
        return

    def _handler():
        relj = _vsp_health_read_release()
        rel_status, rel_pkg, rel_pkg_exists = _vsp_health_release_status(relj)
        rid = _vsp_health_pick_latest_rid()
        out = {
            "ok": True,
            "service_up": True,
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "rid_latest_gate_root": rid,
            "degraded_tools_count": _vsp_health_degraded_tools_count(rid),
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

    app.add_url_rule("/api/vsp/healthz", "vsp_healthz_truefix_v1", _handler, methods=["GET"])
    app.__vsp_healthz_truefix_v1 = True
# ===================== /VSP_P0_HEALTHZ_TRUEFIX_V1 =====================
'''

s = s[:ins_top] + "\n" + block + "\n" + s[ins_top:]

# Now ensure we CALL register after app exists.
# Find first occurrence of "app = Flask(" and insert call right after that statement block.
m_app = re.search(r'^\s*app\s*=\s*Flask\(', s, flags=re.M)
if not m_app:
    # fallback: append near end before __main__
    m_main = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s, flags=re.M)
    ins_call = m_main.start() if m_main else len(s)
    call = "\n# auto-register healthz\ntry:\n    _vsp_register_healthz(app)\nexcept Exception:\n    pass\n"
    s = s[:ins_call] + call + s[ins_call:]
else:
    # insert after the line where app is defined (next newline)
    line_end = s.find("\n", m_app.end())
    if line_end == -1:
        line_end = m_app.end()
    call = "\n# auto-register healthz (truefix)\ntry:\n    _vsp_register_healthz(app)\nexcept Exception:\n    pass\n"
    s = s[:line_end+1] + call + s[line_end+1:]

p.write_text(s, encoding="utf-8")
print("[OK] applied", MARK)
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] healthz truefix installed."
