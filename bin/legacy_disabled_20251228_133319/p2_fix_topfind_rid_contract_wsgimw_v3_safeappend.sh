#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC1="vsp-ui-8910.service"
SVC2="vsp-ui-gateway.service"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head; need curl

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

cp -f "$WSGI" "${WSGI}.bak_topfind_ridfix_v3_${TS}"
echo "[BACKUP] ${WSGI}.bak_topfind_ridfix_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P2_TOPFIND_RID_CONTRACT_WSGIMW_V3"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

patch = r'''

# ===================== VSP_P2_TOPFIND_RID_CONTRACT_WSGIMW_V3 =====================
# Normalize /api/vsp/top_findings_* response: rid MUST equal rid_used when present.
try:
    import json as _json
except Exception:
    _json = None

class _VspTopFindRidContractMW:
    def __init__(self, inner):
        self.inner = inner

    def __call__(self, environ, start_response):
        path = (environ or {}).get("PATH_INFO", "") or ""
        if path.startswith("/api/vsp/top_findings"):
            captured = {"status": None, "headers": None, "exc": None}
            chunks = []

            def _sr(status, headers, exc_info=None):
                captured["status"] = status
                captured["headers"] = list(headers) if headers else []
                captured["exc"] = exc_info
                def _write(b):
                    try:
                        if b:
                            chunks.append(b)
                    except Exception:
                        pass
                return _write

            result = self.inner(environ, _sr)

            try:
                for c in result:
                    if c:
                        chunks.append(c)
            finally:
                try:
                    if hasattr(result, "close"):
                        result.close()
                except Exception:
                    pass

            body = b"".join(chunks) if chunks else b""
            headers = captured.get("headers") or []
            status = captured.get("status") or "200 OK"

            # best-effort JSON detect
            is_json = False
            for k, v in headers:
                if str(k).lower() == "content-type" and "json" in str(v).lower():
                    is_json = True
                    break
            if (not is_json) and body.lstrip().startswith(b"{"):
                is_json = True

            if is_json and _json is not None and body:
                try:
                    j = _json.loads(body.decode("utf-8", "replace"))
                    ru = j.get("rid_used") or j.get("rid_resolved") or j.get("rid_effective")
                    if ru and j.get("rid") != ru:
                        # keep old rid for audit
                        if j.get("rid_raw") is None:
                            j["rid_raw"] = j.get("rid")
                        j["rid"] = ru
                        body = _json.dumps(j, ensure_ascii=False).encode("utf-8")

                        # fix content-length
                        newh = []
                        for k, v in headers:
                            if str(k).lower() == "content-length":
                                continue
                            newh.append((k, v))
                        newh.append(("Content-Length", str(len(body))))
                        headers = newh
                except Exception:
                    pass

            start_response(status, headers, captured.get("exc"))
            return [body]

        return self.inner(environ, start_response)

def _vsp_attach_topfind_rid_contract_mw():
    g = globals()
    # Prefer Flask app.wsgi_app if exists
    a = g.get("app")
    if a is not None and hasattr(a, "wsgi_app"):
        inner = getattr(a, "wsgi_app")
        # avoid double wrap
        if not getattr(inner, "_VSP_TOPFIND_RID_CONTRACT_WRAPPED", False):
            mw = _VspTopFindRidContractMW(inner)
            setattr(mw, "_VSP_TOPFIND_RID_CONTRACT_WRAPPED", True)
            a.wsgi_app = mw
        return True
    # Fallback: wrap callable named application/app
    for name in ("application", "app"):
        inner = g.get(name)
        if callable(inner) and not getattr(inner, "_VSP_TOPFIND_RID_CONTRACT_WRAPPED", False):
            mw = _VspTopFindRidContractMW(inner)
            setattr(mw, "_VSP_TOPFIND_RID_CONTRACT_WRAPPED", True)
            g[name] = mw
            return True
    return False

_vsp_attach_topfind_rid_contract_mw()
# =================== /VSP_P2_TOPFIND_RID_CONTRACT_WSGIMW_V3 ======================

'''

p.write_text(s + patch, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended patch:", MARK)
PY

echo "== [RESTART] =="
if systemctl list-units --type=service --all 2>/dev/null | grep -q "^${SVC1}"; then
  sudo systemctl restart "${SVC1}" || true
fi
if systemctl list-units --type=service --all 2>/dev/null | grep -q "^${SVC2}"; then
  sudo systemctl restart "${SVC2}" || true
fi

echo "== [VERIFY] =="
echo "-- rid_latest --"
curl -fsS --connect-timeout 2 --max-time 6 "$BASE/api/vsp/rid_latest" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest=",j.get("rid"),"via=",j.get("via"))'

echo "-- top_findings --"
curl -fsS --connect-timeout 2 --max-time 25 "$BASE/api/vsp/top_findings_v1?limit=5" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid=",j.get("rid"),"rid_used=",j.get("rid_used"),"rid_raw=",j.get("rid_raw"),"items=",len(j.get("items") or []),"marker=",j.get("marker"))'

echo "[DONE] Expect: rid == rid_used, and rid_raw keeps old value (if it was different)."
