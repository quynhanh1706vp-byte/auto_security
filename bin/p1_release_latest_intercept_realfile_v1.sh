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
cp -f "$WSGI" "${WSGI}.bak_rellatest_${TS}"
echo "[BACKUP] ${WSGI}.bak_rellatest_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# ===================== VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V1 =====================
def _vsp_release_latest_realfile_intercept(wsgi_app):
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
        # mirror headers used elsewhere
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
# ===================== /VSP_P1_RELEASE_LATEST_REALFILE_INTERCEPT_V1 =====================
""")

# Insert block near top (after imports) to keep it visible
ins = s.find("\n", 0)
s2 = block + "\n" + s

# Now wrap application where "app = application" exists (your file has this early)
m = re.search(r'^\s*app\s*=\s*application\s*$', s2, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find line 'app = application' to wrap WSGI safely")

wrap = "\n# [WRAP] release_latest realfile intercept\napplication = _vsp_release_latest_realfile_intercept(application)\napp = application\n"
# Replace only the first 'app = application' occurrence with wrapper (idempotent enough via MARK)
s2 = re.sub(r'^\s*app\s*=\s*application\s*$',
            wrap.rstrip(),
            s2,
            count=1,
            flags=re.M)

p.write_text(s2, encoding="utf-8")
print("[OK] installed release_latest intercept:", MARK)
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] release_latest intercept installed."
