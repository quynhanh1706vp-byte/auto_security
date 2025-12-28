#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P1_AUDIT_PACK_MANIFEST_API_V1"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_auditmanifest_${TS}"
echo "[BACKUP] ${W}.bak_auditmanifest_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P1_AUDIT_PACK_MANIFEST_API_V1" in s:
    print("[SKIP] manifest api already present")
    raise SystemExit(0)

insert = textwrap.dedent(r"""
# ===================== VSP_P1_AUDIT_PACK_MANIFEST_API_V1 =====================
# API: /api/vsp/audit_pack_manifest?rid=<RID>&lite=1(optional)
# Build manifest via the SAME internal calls as audit_pack_download (no tgz).
try:
    import json, time, traceback
    from urllib.parse import parse_qs, quote_plus

    def _wrap_audit_manifest(inner):
        def _wsgi(environ, start_response):
            if (environ.get("PATH_INFO","") or "") != "/api/vsp/audit_pack_manifest":
                return inner(environ, start_response)
            try:
                qs = parse_qs(environ.get("QUERY_STRING","") or "")
                rid = (qs.get("rid") or [""])[0].strip()
                lite = (qs.get("lite") or [""])[0].strip() in ("1","true","yes","on")
                if not rid:
                    b = json.dumps({"ok":False,"err":"missing rid"}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                # reuse internal caller defined in audit pack V2 block if exists
                caller = globals().get("_call_internal")
                if not callable(caller):
                    b = json.dumps({"ok":False,"err":"internal caller not available"}, ensure_ascii=False).encode("utf-8")
                    start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                    return [b]

                items = [
                    "run_gate_summary.json",
                    "run_gate.json",
                    "SUMMARY.txt",
                    "run_manifest.json",
                    "run_evidence_index.json",
                    "reports/findings_unified.csv",
                    "reports/findings_unified.sarif",
                    "reports/findings_unified.html",
                    "reports/findings_unified.pdf",
                ]
                if not lite:
                    items.insert(0, "findings_unified.json")

                included=[]; missing=[]; errors=[]
                for path in items:
                    q = f"rid={quote_plus(rid)}&path={quote_plus(path)}"
                    r = caller(inner, "/api/vsp/run_file_allow", qs=q, method="GET", max_read=5_000_000)
                    if r.get("code") != 200 or r.get("err"):
                        errors.append({"path": path, "code": r.get("code"), "err": r.get("err")})
                        continue
                    body = r.get("body") or b""
                    if not body:
                        missing.append({"path": path, "reason": "empty"})
                        continue
                    # detect run_file_allow error json
                    ct = (r.get("hdr") or {}).get("content-type","").lower()
                    if "application/json" in ct:
                        try:
                            j = json.loads(body.decode("utf-8","replace"))
                            if isinstance(j, dict) and j.get("ok") is False:
                                missing.append({"path": path, "reason": j.get("err") or "not allowed"})
                                continue
                        except Exception:
                            pass
                    included.append({"path": path, "bytes": len(body)})

                out = {
                    "ok": True, "rid": rid, "lite": lite,
                    "included_count": len(included),
                    "missing_count": len(missing),
                    "errors_count": len(errors),
                    "included": included,
                    "missing": missing,
                    "errors": errors,
                    "ts": int(time.time()),
                }
                b = json.dumps(out, ensure_ascii=False).encode("utf-8")
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
            except Exception as e:
                b = json.dumps({"ok":False,"err":str(e),"tb":traceback.format_exc(limit=6)}, ensure_ascii=False).encode("utf-8")
                start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(b)))])
                return [b]
        return _wsgi

    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_audit_manifest(application)
    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_audit_manifest(app)

    print("[VSP_P1_AUDIT_PACK_MANIFEST_API_V1] enabled")
except Exception as _e:
    print("[VSP_P1_AUDIT_PACK_MANIFEST_API_V1] ERROR:", _e)
# ===================== /VSP_P1_AUDIT_PACK_MANIFEST_API_V1 =====================
""").strip("\n")

# append at EOF
p.write_text(s + "\n\n" + insert + "\n", encoding="utf-8")
print("[OK] appended audit pack manifest api")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== smoke manifest (lite) =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); r=(j.get("runs") or [{}])[0]; print(r.get("rid") or r.get("run_id") or "")')"
curl -fsS "$BASE/api/vsp/audit_pack_manifest?rid=$RID&lite=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"inc=",j.get("included_count"),"miss=",j.get("missing_count"),"err=",j.get("errors_count"))'
echo "[DONE]"
