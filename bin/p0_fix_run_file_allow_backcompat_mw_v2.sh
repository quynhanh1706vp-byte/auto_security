#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="${1:-VSP_CI_20251219_092640}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_MW_V2"
cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
if "VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_MW_V2" in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

mw = r'''
# --- VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_MW_V2 ---
# Post-processor: for /api/vsp/run_file_allow responses shaped like {ok:true, data:{...}}
# mirror data keys to top-level so old UI JS keeps working.
import json as _vsp_json_rfa_bc2
import gzip as _vsp_gzip_rfa_bc2

class _VspRunFileAllowBackcompatMwV2:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        if (environ.get("PATH_INFO") or "") != "/api/vsp/run_file_allow":
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        wrote = []
        def _write(b):
            if b:
                wrote.append(b)
        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=list(headers or [])
            captured["exc"]=exc_info
            return _write

        resp_iter = self.app(environ, _sr)
        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []
        exc = captured["exc"]

        body = b"".join(wrote) + b"".join(resp_iter)

        ctype=""
        enc=""
        for k,v in headers:
            lk=(k or "").lower()
            if lk=="content-type": ctype=v or ""
            if lk=="content-encoding": enc=(v or "").lower()

        # only JSON
        if "application/json" not in (ctype or ""):
            start_response(status, headers, exc)
            return [body]

        raw = body
        try:
            if enc=="gzip":
                raw = _vsp_gzip_rfa_bc2.decompress(body)
        except Exception:
            raw = body

        try:
            j = _vsp_json_rfa_bc2.loads(raw.decode("utf-8","ignore") or "{}")
        except Exception:
            start_response(status, headers, exc)
            return [body]

        if isinstance(j, dict) and j.get("ok") is True and isinstance(j.get("data"), dict):
            data = j.get("data") or {}
            # mirror keys to top-level (do not override existing wrapper fields)
            for k,v in data.items():
                if k not in j:
                    j[k]=v

            out_raw = _vsp_json_rfa_bc2.dumps(j, ensure_ascii=False).encode("utf-8")
            out = out_raw
            if enc=="gzip":
                out = _vsp_gzip_rfa_bc2.compress(out_raw)

            new=[]
            for k,v in headers:
                lk=(k or "").lower()
                if lk=="content-length":
                    continue
                new.append((k,v))
            # ensure no-store and correct length
            if not any((k or "").lower()=="cache-control" for k,_ in new):
                new.append(("Cache-Control","no-store"))
            new.append(("Content-Length", str(len(out))))
            start_response(status, new, exc)
            return [out]

        start_response(status, headers, exc)
        return [body]

try:
    application = _VspRunFileAllowBackcompatMwV2(application)
except Exception:
    pass
# --- /VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_MW_V2 ---
# VSP_P0_RUN_FILE_ALLOW_BACKCOMPAT_MW_V2
'''
s2 = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s2, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended backcompat post-processor MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.8
fi

echo "== [VERIFY] run_gate_summary now has counts_total at TOP-LEVEL =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_data=",isinstance(j.get("data"),dict),"has_counts_top=",("counts_total" in j),"from=",j.get("from"))'

echo "== [VERIFY] findings_unified now has findings at TOP-LEVEL =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_data=",isinstance(j.get("data"),dict),"top_findings=",isinstance(j.get("findings"),list),"data_findings=",isinstance((j.get("data") or {}).get("findings"),list))'

ok "DONE"
