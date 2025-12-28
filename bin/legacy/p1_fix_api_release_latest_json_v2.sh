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
cp -f "$WSGI" "${WSGI}.bak_reljson_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_reljson_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_API_RELEASE_LATEST_JSON_V2"
if marker in s:
    print("[OK] marker already present:", marker)
else:
    blk = textwrap.dedent(r"""
    # ===================== VSP_P1_API_RELEASE_LATEST_JSON_V2 =====================
    # Provide /api/vsp/release_latest.json (ALWAYS 200) to support Release Card v2.
    # - resolves file across common roots
    # - returns ok/exists + package_exists for STALE amber in UI
    # ============================================================================

    def _vsp__get_flask_app_v2():
        # Try common names used in this gateway.
        for name in ("app", "application"):
            obj = globals().get(name)
            if obj is None:
                continue
            # Flask app has add_url_rule / view_functions / route
            if hasattr(obj, "add_url_rule") and hasattr(obj, "view_functions"):
                return obj
        return None

    def _vsp__release_latest_search_paths_v2():
        from pathlib import Path as _Path
        here = _Path(__file__).resolve()
        ui_root = here.parent  # .../SECURITY_BUNDLE/ui
        bundle_root = ui_root.parent  # .../SECURITY_BUNDLE

        cands = [
            ui_root / "out_ci" / "releases" / "release_latest.json",
            ui_root / "out" / "releases" / "release_latest.json",
            bundle_root / "out_ci" / "releases" / "release_latest.json",
            bundle_root / "out" / "releases" / "release_latest.json",
        ]
        return cands

    def _vsp__read_release_latest_v2():
        import json, time
        from pathlib import Path as _Path

        for f in _vsp__release_latest_search_paths_v2():
            try:
                if f.is_file():
                    j = json.loads(f.read_text(encoding="utf-8", errors="replace"))
                    pkg = (j.get("package") or "").strip()
                    sha = (j.get("sha") or "").strip()
                    ts  = (j.get("ts") or "").strip()

                    # resolve package existence:
                    pkg_exists = None
                    pkg_abs = None
                    if pkg:
                        # allow "out_ci/releases/xxx.tgz" or absolute
                        p2 = _Path(pkg)
                        if not p2.is_absolute():
                            # interpret relative to UI root and bundle root
                            ui_root = _Path(__file__).resolve().parent
                            bundle_root = ui_root.parent
                            cand = ui_root / pkg
                            cand2 = bundle_root / pkg
                            if cand.is_file():
                                pkg_abs = str(cand)
                                pkg_exists = True
                            elif cand2.is_file():
                                pkg_abs = str(cand2)
                                pkg_exists = True
                            else:
                                pkg_abs = str(cand)  # best-effort for debug
                                pkg_exists = False
                        else:
                            pkg_abs = str(p2)
                            pkg_exists = bool(p2.is_file())

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
            "searched": [str(x) for x in _vsp__release_latest_search_paths_v2()],
            "ts": __import__("time").time(),
        }

    def api_vsp_release_latest_json_v2():
        # ALWAYS 200 to avoid console spam; UI decides STALE.
        try:
            from flask import jsonify
        except Exception:
            # very defensive fallback
            import json
            return (json.dumps(_vsp__read_release_latest_v2()), 200, {"Content-Type":"application/json"})
        return jsonify(_vsp__read_release_latest_v2()), 200

    _A = _vsp__get_flask_app_v2()
    if _A is not None:
        ep = "api_vsp_release_latest_json_v2"
        if not hasattr(_A, "view_functions") or ep not in getattr(_A, "view_functions", {}):
            try:
                _A.add_url_rule("/api/vsp/release_latest.json", ep, api_vsp_release_latest_json_v2, methods=["GET"])
            except Exception:
                pass
    # ===================== /VSP_P1_API_RELEASE_LATEST_JSON_V2 =====================
    """).lstrip("\n")

    s2 = s.rstrip() + "\n\n" + blk + "\n"
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended block:", marker)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile:", p)
PY

echo "== restart UI =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== verify endpoint (expect HTTP 200 + JSON) =="
curl -sS -D /tmp/_rel_hdr.txt -o /tmp/_rel_body.txt "$BASE/api/vsp/release_latest.json" || true
head -n 1 /tmp/_rel_hdr.txt | sed 's/\r$//'
echo "BODY_HEAD: $(head -c 260 /tmp/_rel_body.txt | tr '\n' ' ')"
echo "[DONE]"
