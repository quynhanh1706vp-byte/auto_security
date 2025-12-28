#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ss

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_broken_rellatest_${TS}"
echo "[SNAPSHOT BROKEN] ${WSGI}.bak_broken_rellatest_${TS}"

echo "== [1] restore known-good backup (pre v1 intercept) =="
# pick latest bak_rellatest_* if exists, else newest compiling backup
GOOD="$(ls -1t ${WSGI}.bak_rellatest_* 2>/dev/null | head -n1 || true)"
if [ -z "$GOOD" ]; then
  echo "[WARN] no bak_rellatest found; searching any compiling backup..."
  GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile
p = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
for b in baks[:200]:
    try:
        tmp = Path("/tmp/_wsgi_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        print(b.as_posix())
        raise SystemExit(0)
    except Exception:
        continue
raise SystemExit(2)
PY
)" || { echo "[ERR] cannot find compiling backup"; exit 2; }
fi

echo "[RESTORE] $GOOD -> $WSGI"
cp -f "$GOOD" "$WSGI"

echo "== [2] apply SAFEAPPEND v2 intercept at EOF (no app=application replacement) =="
python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove old V1 block if any (in case GOOD wasn't fully clean)
s = re.sub(
    r"\n# ===================== VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V1 =====================.*?"
    r"# ===================== /VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V1 =====================\n",
    "\n",
    s,
    flags=re.S,
)
# Remove old wrapper comment if any
s = re.sub(r"\n# \[WRAP\] release_latest realfile intercept.*?\napp\s*=\s*application\s*\n", "\n", s, flags=re.S)

MARK = "VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V2_SAFEAPPEND"
if MARK in s:
    p.write_text(s, encoding="utf-8")
    print("[OK] already has", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V2_SAFEAPPEND =====================
def _vsp_release_latest_realfile_intercept_v2(wsgi_app):
    import json, time, os
    from pathlib import Path

    def _read_release_latest():
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
                    return json.loads(rp.read_text(encoding="utf-8", errors="replace")), str(rp)
            except Exception:
                continue
        return {}, ""

    def _pkg_exists(pkg: str):
        if not pkg:
            return (False, "")
        pkg = pkg.strip()
        pp = Path(pkg) if pkg.startswith("/") else (Path("/home/test/Data/SECURITY_BUNDLE") / pkg)
        ok = pp.is_file() and pp.stat().st_size > 0
        return (ok, str(pp))

    def _resp_json(start_response, payload: dict):
        body = (json.dumps(payload, ensure_ascii=False)).encode("utf-8")
        headers = [
            ("Content-Type", "application/json; charset=utf-8"),
            ("Cache-Control", "no-store"),
            ("Content-Length", str(len(body))),
        ]
        if payload.get("release_ts"):  headers.append(("X-VSP-RELEASE-TS", str(payload["release_ts"])))
        if payload.get("release_sha"): headers.append(("X-VSP-RELEASE-SHA", str(payload["release_sha"])))
        if payload.get("release_pkg"): headers.append(("X-VSP-RELEASE-PKG", str(payload["release_pkg"])))
        headers.append(("X-VSP-RELEASE-LATEST", "ok"))
        start_response("200 OK", headers)
        return [body]

    def _app(environ, start_response):
        try:
            if environ.get("PATH_INFO") == "/api/vsp/release_latest":
                relj, src = _read_release_latest()
                pkg = str(relj.get("release_pkg") or "").strip()
                ok_pkg, abs_pkg = _pkg_exists(pkg)
                out = {
                    "ok": True,
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                    "release_status": "OK" if ok_pkg else "STALE",
                    "release_ts": relj.get("release_ts",""),
                    "release_sha": relj.get("release_sha",""),
                    "release_pkg": pkg,
                    "release_pkg_exists": ok_pkg,
                    "release_pkg_abs": abs_pkg,
                    "source_json": src,
                }
                return _resp_json(start_response, out)
        except Exception as e:
            out = {"ok": True, "release_status": "STALE", "err": str(e)}
            return _resp_json(start_response, out)
        return wsgi_app(environ, start_response)

    return _app
# ===================== /VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V2_SAFEAPPEND =====================

# Activate at EOF (safe order: after all other wrappers)
try:
    application = _vsp_release_latest_realfile_intercept_v2(application)
    app = application
except Exception:
    pass
""")

p.write_text(s.rstrip() + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended", MARK)
PY

echo "== [3] compile check =="
python3 -m py_compile "$WSGI"

echo "== [4] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.4

echo "== [5] verify port/listener =="
ss -ltnp 2>/dev/null | grep -n ":8910" || echo "[WARN] :8910 not listening yet"

echo "== [6] verify healthz and release_latest =="
curl -fsS "$BASE/api/vsp/healthz" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("OK healthz rid=", j.get("rid_latest_gate_root"))'
curl -fsS "$BASE/api/vsp/release_latest" | python3 -m json.tool

echo "[DONE] recovered + v2 intercept active."
