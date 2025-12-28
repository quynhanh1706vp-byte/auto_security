#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need zip; need systemctl; need curl; need mkdir

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
WSGI="wsgi_vsp_ui_gateway.py"

# Choose RID: arg1 or rid_latest
RID="${1:-}"
if [ -z "$RID" ]; then
  RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print((json.load(sys.stdin).get("rid") or "").strip())')"
fi
[ -n "$RID" ] || { echo "[ERR] RID empty"; exit 2; }
echo "[RID] $RID"

# Locate run dir (out/out_ci)
RUN_DIR=""
for d in \
  "/home/test/Data/SECURITY_BUNDLE/out/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/out_ci/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/ui/out/$RID" \
  "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/$RID"
do
  if [ -d "$d" ]; then RUN_DIR="$d"; break; fi
done
[ -n "$RUN_DIR" ] || { echo "[ERR] run dir not found for RID=$RID"; exit 2; }
echo "[RUN_DIR] $RUN_DIR"

REL_DIR="/home/test/Data/SECURITY_BUNDLE/ui/releases"
mkdir -p "$REL_DIR"

TS="$(date +%Y%m%d_%H%M%S)"
PKG="$REL_DIR/VSP_RELEASE_${RID}_${TS}.zip"
MAN="$REL_DIR/VSP_RELEASE_${RID}_${TS}.manifest.json"

echo "== [1] pack zip =="
# Pack "reports" + key artifacts if exist (do not fail if missing)
tmp="$(mktemp -d /tmp/vsp_relpack_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/payload"

# Copy reports/ if exists
if [ -d "$RUN_DIR/reports" ]; then
  mkdir -p "$tmp/payload/reports"
  cp -a "$RUN_DIR/reports/." "$tmp/payload/reports/" || true
fi

# Copy important top-level artifacts if exist
for f in \
  "run_gate_summary.json" \
  "reports/run_gate_summary.json" \
  "findings_unified.json" \
  "reports/findings_unified.json" \
  "reports/findings_unified.csv" \
  "reports/findings_unified.sarif" \
  "SUMMARY.txt" \
  "run_manifest.json" \
  "verdict_4t.json" \
  "run_gate.json"
do
  if [ -f "$RUN_DIR/$f" ]; then
    mkdir -p "$tmp/payload/$(dirname "$f")"
    cp -a "$RUN_DIR/$f" "$tmp/payload/$f"
  fi
done

( cd "$tmp/payload" && zip -qr "$PKG" . )
echo "[OK] package: $PKG"

echo "== [2] write manifest =="
python3 - <<PY
import json, os, time, hashlib
rid = ${RID!r}
pkg = ${PKG!r}
run_dir = ${RUN_DIR!r}

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
  "run_dir": run_dir,
  "notes": "P1 release package for commercial UI",
  "download_url": f"/api/vsp/release_download?rid={rid}",
  "audit_url": f"/api/vsp/release_audit?rid={rid}"
}
with open(${MAN!r}, "w", encoding="utf-8") as f:
    json.dump(m, f, ensure_ascii=False, indent=2)
print("[OK] manifest:", ${MAN!r})
PY

echo "== [3] patch WSGI: release_latest + release_download endpoints via WSGI middleware (safe) =="
cp -f "$WSGI" "${WSGI}.bak_release_${TS}"
echo "[BACKUP] ${WSGI}.bak_release_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RELEASE_WSGI_MW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# ===================== VSP_P1_RELEASE_WSGI_MW_V1 =====================
# Provide:
#  - GET /api/vsp/release_latest  -> JSON manifest for latest release in ui/releases
#  - GET /api/vsp/release_download?rid=... -> returns ZIP bytes
#  - GET /api/vsp/release_audit?rid=... -> returns manifest JSON for that rid (latest match)
# Implemented as WSGI wrapper on `application` to avoid Flask route dependency.

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
            # also provide absolute-ish urls (relative)
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
PY

echo "== [4] restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] $SVC active" || { echo "[ERR] $SVC not active"; systemctl --no-pager status "$SVC" -n 60 || true; exit 2; }

echo "== [5] verify endpoints =="
curl -fsS "$BASE/api/vsp/release_latest" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"download_url=",j.get("download_url"))'
curl -fsS -o /tmp/vsp_release_test.zip "$BASE/api/vsp/release_download?rid=$RID"
echo "[OK] downloaded bytes=$(wc -c </tmp/vsp_release_test.zip) => /tmp/vsp_release_test.zip"
