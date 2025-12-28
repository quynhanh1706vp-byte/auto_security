#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_audit_v2_${TS}"
echo "[BACKUP] ${W}.bak_audit_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

start = "# ===================== VSP_P1_AUDIT_PACK_DOWNLOAD_V1 ====================="
end   = "# ===================== /VSP_P1_AUDIT_PACK_DOWNLOAD_V1 ====================="
if start not in s or end not in s:
    print("[ERR] audit pack v1 markers not found")
    raise SystemExit(2)

block = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_DOWNLOAD_V1 =====================
# Upgraded to V2: build pack via internal WSGI calls to /api/vsp/run_file_allow (no filesystem RID lookup).
# API: /api/vsp/audit_pack_download?rid=<RID>&lite=1(optional)
# NEVER 500: always returns tgz or JSON error 200.
try:
    import io, json, tarfile, time, traceback
    from urllib.parse import parse_qs, quote_plus

    def _json200(start_response, obj):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-store"),
            ("Content-Length", str(len(b))),
        ])
        return [b]

    def _call_internal(inner, path, qs="", method="GET", max_read=50_000_000):
        # Internal WSGI subrequest (no loopback HTTP)
        import io as _io, sys as _sys
        env = {
            "REQUEST_METHOD": method,
            "PATH_INFO": path,
            "QUERY_STRING": qs or "",
            "SCRIPT_NAME": "",
            "SERVER_PROTOCOL": "HTTP/1.1",
            "SERVER_NAME": "127.0.0.1",
            "SERVER_PORT": "8910",
            "REMOTE_ADDR": "127.0.0.1",
            "wsgi.version": (1,0),
            "wsgi.url_scheme": "http",
            "wsgi.input": _io.BytesIO(b""),
            "wsgi.errors": _sys.stderr,
            "wsgi.multithread": True,
            "wsgi.multiprocess": True,
            "wsgi.run_once": False,
            "HTTP_HOST": "127.0.0.1:8910",
            "HTTP_USER_AGENT": "VSP-AuditPack/2.0",
            "HTTP_ACCEPT": "*/*",
            "HTTP_CONNECTION": "close",
        }
        st = {"v":"500 INTERNAL"}
        hdrs = {"v":[]}
        def _sr(status, headers, exc_info=None):
            st["v"] = status
            hdrs["v"] = headers or []
            return None

        t0 = time.time()
        body = b""
        err = None
        try:
            it = inner(env, _sr)
            for chunk in it or []:
                if not chunk:
                    continue
                if isinstance(chunk, str):
                    chunk = chunk.encode("utf-8","replace")
                body += chunk
                if len(body) >= max_read:
                    break
            try:
                if hasattr(it, "close"): it.close()
            except Exception:
                pass
        except Exception as e:
            err = str(e)

        ms = int((time.time()-t0)*1000)
        try:
            code = int((st["v"].split(" ",1)[0] or "0").strip())
        except Exception:
            code = None
        # headers map
        hm = {}
        try:
            for k,v in (hdrs["v"] or []):
                if k:
                    hm[str(k).lower()] = str(v)
        except Exception:
            pass
        return {"code": code, "ms": ms, "body": body, "err": err, "hdr": hm}

    def _wrap_audit_pack(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/audit_pack_download":
                return inner(environ, start_response)
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0].strip()
                lite = (qs.get("lite") or [""])[0].strip() in ("1","true","yes","on")
                if not rid:
                    return _json200(start_response, {"ok": False, "err": "missing rid"})

                # files to fetch via run_file_allow
                items = [
                    ("run_gate_summary.json", "run_gate_summary.json"),
                    ("run_gate.json", "run_gate.json"),
                    ("SUMMARY.txt", "SUMMARY.txt"),
                    ("run_manifest.json", "run_manifest.json"),
                    ("run_evidence_index.json", "run_evidence_index.json"),
                    ("reports/findings_unified.csv", "reports/findings_unified.csv"),
                    ("reports/findings_unified.sarif", "reports/findings_unified.sarif"),
                    ("reports/findings_unified.html", "reports/findings_unified.html"),
                    ("reports/findings_unified.pdf", "reports/findings_unified.pdf"),
                ]
                if not lite:
                    items.insert(0, ("findings_unified.json", "findings_unified.json"))

                included = []
                missing = []
                errors = []

                bio = io.BytesIO()
                with tarfile.open(fileobj=bio, mode="w:gz") as tf:
                    for path, arc in items:
                        q = f"rid={quote_plus(rid)}&path={quote_plus(path)}"
                        r = _call_internal(inner, "/api/vsp/run_file_allow", qs=q, method="GET", max_read=60_000_000)
                        if r.get("code") != 200 or r.get("err"):
                            errors.append({"path": path, "code": r.get("code"), "err": r.get("err")})
                            continue

                        body = r.get("body") or b""
                        if not body:
                            missing.append({"path": path, "reason": "empty"})
                            continue

                        # run_file_allow usually returns JSON-parsed content (already JSON body), or {"ok":false,...}
                        is_json = ("application/json" in (r.get("hdr",{}).get("content-type","").lower()))
                        if is_json:
                            try:
                                j = json.loads(body.decode("utf-8","replace"))
                                if isinstance(j, dict) and j.get("ok") is False and ("err" in j or "error" in j):
                                    missing.append({"path": path, "reason": j.get("err") or j.get("error")})
                                    continue
                                body = json.dumps(j, ensure_ascii=False, indent=2).encode("utf-8")
                            except Exception:
                                # keep raw
                                pass

                        info = tarfile.TarInfo(name=arc)
                        info.size = len(body)
                        info.mtime = int(time.time())
                        tf.addfile(info, io.BytesIO(body))
                        included.append({"path": path, "arc": arc, "bytes": len(body)})

                    manifest = {
                        "ok": True,
                        "rid": rid,
                        "lite": lite,
                        "included": included,
                        "missing": missing,
                        "errors": errors,
                        "ts": int(time.time()),
                    }
                    mb = json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8")
                    mi = tarfile.TarInfo(name="manifest.json")
                    mi.size = len(mb)
                    mi.mtime = int(time.time())
                    tf.addfile(mi, io.BytesIO(mb))

                data = bio.getvalue()
                name = f"audit_pack_{rid}.tgz" if not lite else f"audit_pack_{rid}_lite.tgz"
                start_response("200 OK", [
                    ("Content-Type", "application/gzip"),
                    ("Content-Disposition", f'attachment; filename="{name}"'),
                    ("Cache-Control","no-store"),
                    ("X-VSP-AUDIT-PACK","2"),
                    ("Content-Length", str(len(data))),
                ])
                return [data]

            except Exception as e:
                return _json200(start_response, {"ok": False, "err": str(e), "tb": traceback.format_exc(limit=6)})
        return _wsgi

    # wrap last
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_audit_pack(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_audit_pack(app)

    print("[VSP_P1_AUDIT_PACK_DOWNLOAD_V2] enabled")
except Exception as _e:
    print("[VSP_P1_AUDIT_PACK_DOWNLOAD_V2] ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_DOWNLOAD_V1 =====================
""").strip("\n")

pat = re.compile(re.escape(start) + r".*?" + re.escape(end), re.S)
s2 = pat.sub(block, s, count=1)
p.write_text(s2, encoding="utf-8")
print("[OK] replaced audit pack impl => V2 via run_file_allow")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke: audit pack HEAD + bytes (must be gzip + big) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
echo "[RID]=$RID"
U="$BASE/api/vsp/audit_pack_download?rid=$RID&lite=1"
H="/tmp/vsp_audit_hdr.$$"
B="/tmp/vsp_audit_body.$$"
curl -sS -D "$H" "$U" -o "$B" || true
echo "-- HEAD --"
sed -n '1,25p' "$H" || true
echo "-- BYTES --"
python3 - <<PY
import os
print("bytes=", os.path.getsize("$B") if os.path.exists("$B") else -1)
PY
echo "-- If still JSON error, show body head --"
head -c 220 "$B" 2>/dev/null || true; echo
rm -f "$H" "$B" || true
echo "[DONE]"
