#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls; need zip; need wc

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"
REL_DIR="/home/test/Data/SECURITY_BUNDLE/ui/releases"
mkdir -p "$REL_DIR"

RID="${1:-}"
if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())')"
fi
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }
echo "[RID] $RID"

# Pick latest package zip for this RID
PKG="$(ls -1t "$REL_DIR"/VSP_RELEASE_${RID}_*.zip 2>/dev/null | head -n 1 || true)"
[ -n "$PKG" ] || { echo "[ERR] no package zip found for RID=$RID in $REL_DIR"; exit 2; }
echo "[PKG] $PKG"

TS="$(basename "$PKG" | sed -n 's/.*_\([0-9]\{8\}_[0-9]\{6\}\)\.zip/\1/p')"
[ -n "$TS" ] || TS="$(date +%Y%m%d_%H%M%S)"
MAN="$REL_DIR/VSP_RELEASE_${RID}_${TS}.manifest.json"

echo "== [1] write manifest =="
python3 - "$RID" "$PKG" "$MAN" <<'PY'
import sys, json, os, time, hashlib
rid, pkg, man = sys.argv[1], sys.argv[2], sys.argv[3]

def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for ch in iter(lambda: f.read(1024*1024), b''):
            h.update(ch)
    return h.hexdigest()

m = {
  "ok": True,
  "rid": rid,
  "created_ts": int(time.time()),
  "package_path": pkg,
  "package_sha256": sha256(pkg) if os.path.exists(pkg) else None,
  "notes": "P1 release package for commercial UI",
  "download_url": f"/api/vsp/release_download?rid={rid}",
  "audit_url": f"/api/vsp/release_audit?rid={rid}"
}
with open(man, "w", encoding="utf-8") as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
print("[OK] manifest:", man)
PY

echo "== [2] ensure WSGI release endpoints (middleware) =="
cp -f "$WSGI" "${WSGI}.bak_release_register_${TS}"
echo "[BACKUP] ${WSGI}.bak_release_register_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_RELEASE_WSGI_MW_V1"
if MARK not in s:
    block = r'''
# ===================== VSP_P1_RELEASE_WSGI_MW_V1 =====================
def _vsp__latest_release_manifest_v1():
    try:
        import json
        from pathlib import Path
        rel = Path("/home/test/Data/SECURITY_BUNDLE/ui/releases")
        if not rel.exists():
            return None
        mans = sorted(rel.glob("VSP_RELEASE_*_*.manifest.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        if not mans:
            return None
        j = json.loads(mans[0].read_text(encoding="utf-8", errors="replace"))
        j["manifest_path"] = str(mans[0])
        return j
    except Exception:
        return None

def _vsp__find_manifest_for_rid_v1(rid):
    try:
        import json
        from pathlib import Path
        rel = Path("/home/test/Data/SECURITY_BUNDLE/ui/releases")
        mans = sorted(rel.glob(f"VSP_RELEASE_{rid}_*.manifest.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        if not mans:
            return None
        j = json.loads(mans[0].read_text(encoding="utf-8", errors="replace"))
        j["manifest_path"] = str(mans[0])
        return j
    except Exception:
        return None

def _vsp__wsgi_release_mw_v1(_app):
    import json, time, os
    from urllib.parse import parse_qs

    def _resp_json(start_response, obj, status="200 OK"):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response(status, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(body))),
        ])
        return [body]

    def _mw(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")

        if path == "/api/vsp/release_latest":
            j = _vsp__latest_release_manifest_v1()
            if not j:
                return _resp_json(start_response, {"ok": False, "reason":"no_release", "ts": int(time.time())})
            j["ok"] = True
            j["ts"] = int(time.time())
            return _resp_json(start_response, j)

        if path == "/api/vsp/release_audit":
            rid = (qs.get("rid",[""])[0] or "").strip()
            j = _vsp__find_manifest_for_rid_v1(rid) if rid else None
            if not j:
                return _resp_json(start_response, {"ok": False, "rid": rid, "reason":"manifest_not_found", "ts": int(time.time())})
            j["ok"] = True
            j["ts"] = int(time.time())
            return _resp_json(start_response, j)

        if path == "/api/vsp/release_download":
            rid = (qs.get("rid",[""])[0] or "").strip()
            j = _vsp__find_manifest_for_rid_v1(rid) if rid else None
            if not j:
                return _resp_json(start_response, {"ok": False, "rid": rid, "reason":"manifest_not_found"}, "404 Not Found")
            pkg = j.get("package_path") or ""
            if not pkg or (not os.path.exists(pkg)):
                return _resp_json(start_response, {"ok": False, "rid": rid, "reason":"package_missing"}, "404 Not Found")
            try:
                with open(pkg, "rb") as f:
                    data = f.read()
                start_response("200 OK", [
                    ("Content-Type","application/zip"),
                    ("Content-Disposition", f'attachment; filename="{os.path.basename(pkg)}"'),
                    ("Cache-Control","no-store"),
                    ("Content-Length", str(len(data))),
                ])
                return [data]
            except Exception:
                return _resp_json(start_response, {"ok": False, "rid": rid, "reason":"read_failed"}, "500 Internal Server Error")

        return _app(environ, start_response)

    return _mw

try:
    application = _vsp__wsgi_release_mw_v1(application)
    print("[VSP_P1_RELEASE_WSGI_MW_V1] installed on application")
except Exception as _e:
    try:
        print("[VSP_P1_RELEASE_WSGI_MW_V1] install failed:", repr(_e))
    except Exception:
        pass
# =================== end VSP_P1_RELEASE_WSGI_MW_V1 ===================
'''.strip("\n") + "\n"
    s = s + "\n\n" + block
    p.write_text(s, encoding="utf-8")
    py_compile.compile(str(p), doraise=True)
    print("[OK] patched:", MARK)
else:
    print("[OK] already present:", MARK)
PY

echo "== [3] restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] $SVC active" || { echo "[ERR] $SVC not active"; systemctl --no-pager status "$SVC" -n 60 || true; exit 2; }

echo "== [4] verify endpoints =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"download_url=",j.get("download_url"))'
curl -fsS -o /tmp/vsp_release_test.zip "$BASE/api/vsp/release_download?rid=$RID"
echo "[OK] downloaded bytes=$(wc -c </tmp/vsp_release_test.zip) => /tmp/vsp_release_test.zip"
