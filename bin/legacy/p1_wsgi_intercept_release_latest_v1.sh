#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep

WSGI="wsgi_vsp_ui_gateway.py"
SVC="vsp-ui-8910.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_relwsgi_${TS}"
echo "[BACKUP] ${WSGI}.bak_relwsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_WSGI_INTERCEPT_RELEASE_LATEST_JSON_V1"
if marker in s:
    print("[OK] marker already present:", marker)
else:
    blk = textwrap.dedent(r"""
    # ===================== VSP_P1_WSGI_INTERCEPT_RELEASE_LATEST_JSON_V1 =====================
    # Intercept /api/vsp/release_latest.json at WSGI layer (ALWAYS 200) to avoid 404 spam and
    # support Release Card v2 STALE/NO-PKG logic.
    # ============================================================================

    def _vsp__release_latest_payload_v1():
        import json, time
        from pathlib import Path as _P

        here = _P(__file__).resolve()
        ui_root = here.parent
        bundle_root = ui_root.parent

        cands = [
            ui_root / "out_ci" / "releases" / "release_latest.json",
            ui_root / "out" / "releases" / "release_latest.json",
            bundle_root / "out_ci" / "releases" / "release_latest.json",
            bundle_root / "out" / "releases" / "release_latest.json",
        ]

        for f in cands:
            try:
                if f.is_file():
                    j = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                    pkg = (j.get("package") or "").strip()
                    sha = (j.get("sha") or "").strip()
                    ts  = (j.get("ts") or "").strip()

                    pkg_exists = None
                    pkg_abs = None
                    if pkg:
                        p2 = _P(pkg)
                        if not p2.is_absolute():
                            cand1 = ui_root / pkg
                            cand2 = bundle_root / pkg
                            if cand1.is_file():
                                pkg_abs = str(cand1); pkg_exists = True
                            elif cand2.is_file():
                                pkg_abs = str(cand2); pkg_exists = True
                            else:
                                pkg_abs = str(cand1); pkg_exists = False
                        else:
                            pkg_abs = str(p2); pkg_exists = bool(p2.is_file())

                    return {
                        "ok": True,
                        "exists": True,
                        "source": str(f),
                        "ts": ts,
                        "package": pkg,
                        "sha": sha,
                        "package_exists": pkg_exists,
                        "package_abs": pkg_abs,
                    }
            except Exception:
                continue

        return {
            "ok": False,
            "exists": False,
            "error": "RELEASE_LATEST_NOT_FOUND",
            "searched": [str(x) for x in cands],
            "ts": time.time(),
        }

    def _vsp__wsgi_intercept_release_latest_json_v1(_next):
        def _app(environ, start_response):
            path = (environ.get("PATH_INFO") or "").rstrip("/")
            if path == "/api/vsp/release_latest.json":
                import json
                payload = _vsp__release_latest_payload_v1()
                body = (json.dumps(payload, ensure_ascii=False)).encode("utf-8")
                headers = [
                    ("Content-Type","application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("Cache-Control","no-store"),
                    ("X-VSP-HOTFIX","wsgi_release_latest_v1"),
                ]
                start_response("200 OK", headers)
                return [body]
            return _next(environ, start_response)
        return _app

    try:
        application = _vsp__wsgi_intercept_release_latest_json_v1(application)
    except Exception:
        pass
    # ===================== /VSP_P1_WSGI_INTERCEPT_RELEASE_LATEST_JSON_V1 =====================
    """).lstrip("\n")

    s2 = s.rstrip() + "\n\n" + blk + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended:", marker)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile:", p)
PY

echo "== restart UI =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== verify (must be HTTP 200 + X-VSP-HOTFIX) =="
curl -sS -D /tmp/_rel_hdr.txt -o /tmp/_rel_body.txt "$BASE/api/vsp/release_latest.json" || true
head -n 5 /tmp/_rel_hdr.txt | sed 's/\r$//'
echo "BODY_HEAD: $(head -c 260 /tmp/_rel_body.txt | tr '\n' ' ')"
echo "[DONE]"
