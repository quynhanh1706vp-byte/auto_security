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
cp -f "$WSGI" "${WSGI}.bak_release_latest_${TS}"
echo "[BACKUP] ${WSGI}.bak_release_latest_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_API_RELEASE_LATEST_JSON_V1"

if marker in s:
    print("[OK] marker already present, skip append")
else:
    blk = r'''
# ===================== VSP_P1_API_RELEASE_LATEST_JSON_V1 =====================
# Provide /api/vsp/release_latest.json for Runs "Current Release" card (NO_PKG/STALE/OK)
# - Reads release_latest.json from common roots (no user-supplied path)
# - Resolves package path safely (absolute or relative under SECURITY_BUNDLE roots)
# - Always returns HTTP 200 JSON (ok=true; status indicates state)
# ============================================================================

def _vsp__now_ts_int():
    try:
        import time
        return int(time.time())
    except Exception:
        return 0

def _vsp__release_latest_json_paths_v1():
    # keep in sync with ops scripts
    return [
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/ui/out/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/out/releases/release_latest.json",
    ]

def _vsp__resolve_pkg_path_v1(pkg: str, json_path: str):
    try:
        from pathlib import Path
        pkg = (pkg or "").strip()
        if not pkg:
            return None
        cand = []
        p = Path(pkg)
        if p.is_absolute():
            cand.append(p)
        else:
            # try relative under known roots
            cand.append(Path("/home/test/Data/SECURITY_BUNDLE/ui") / pkg)
            cand.append(Path("/home/test/Data/SECURITY_BUNDLE") / pkg)
            # also relative to json directory
            try:
                cand.append(Path(json_path).parent.parent.parent / pkg)
            except Exception:
                pass
        for c in cand:
            try:
                if c.exists() and c.is_file():
                    return str(c)
            except Exception:
                continue
        return None
    except Exception:
        return None

def _vsp__load_release_latest_v1():
    import json, os
    out = {
        "ok": True,
        "status": "NO_PKG",   # NO_PKG | STALE | OK | ERROR
        "ts": None,
        "package": None,
        "sha": None,
        "json_path": None,
        "package_exists": None,
        "package_path": None,
        "_ts": _vsp__now_ts_int(),
    }

    jp = None
    for path in _vsp__release_latest_json_paths_v1():
        try:
            if os.path.isfile(path):
                jp = path
                break
        except Exception:
            continue

    if not jp:
        return out

    out["json_path"] = jp
    try:
        with open(jp, "r", encoding="utf-8") as f:
            j = json.load(f)
    except Exception as e:
        out["ok"] = False
        out["status"] = "ERROR"
        out["error"] = "RELEASE_JSON_PARSE_ERROR"
        out["detail"] = str(e)
        return out

    out["ts"] = j.get("ts") or j.get("time") or j.get("created_at")
    out["package"] = j.get("package") or j.get("pkg") or j.get("path")
    out["sha"] = j.get("sha") or j.get("sha256") or j.get("hash")

    pkg_path = _vsp__resolve_pkg_path_v1(str(out["package"] or ""), jp)
    if not out["package"]:
        out["status"] = "NO_PKG"
        out["package_exists"] = None
        out["package_path"] = None
        return out

    if pkg_path:
        out["status"] = "OK"
        out["package_exists"] = True
        out["package_path"] = pkg_path
    else:
        out["status"] = "STALE"
        out["package_exists"] = False
        out["package_path"] = None

    return out

try:
    from flask import jsonify
    _vsp_app = globals().get("app") or globals().get("application")
    if _vsp_app:
        @_vsp_app.route("/api/vsp/release_latest.json", methods=["GET"])
        def api_vsp_release_latest_json_v1():
            return jsonify(_vsp__load_release_latest_v1()), 200
except Exception:
    pass

# ===================== /VSP_P1_API_RELEASE_LATEST_JSON_V1 =====================
'''
    p.write_text(s + ("\n" if not s.endswith("\n") else "") + blk, encoding="utf-8")
    print("[OK] appended block:", marker)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile:", p)
PY

echo "== restart UI =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== verify endpoint (must be 200) =="
curl -sS -D /tmp/_rel_hdr.txt -o /tmp/_rel_body.txt "$BASE/api/vsp/release_latest.json" || true
head -n 1 /tmp/_rel_hdr.txt | sed 's/\r$//'
echo "BODY_HEAD: $(head -c 220 /tmp/_rel_body.txt | tr '\n' ' ')"
echo

echo "[DONE] release_latest API added"
