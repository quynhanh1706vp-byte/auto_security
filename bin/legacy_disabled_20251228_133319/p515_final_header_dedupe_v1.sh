#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
T="wsgi_vsp_ui_gateway.py"
[ -f "$T" ] || { echo "[ERR] missing $T"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p515_${TS}"
mkdir -p "$OUT"
cp -f "$T" "$OUT/$(basename "$T").bak_${TS}"
echo "[OK] backup => $OUT/$(basename "$T").bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys, re
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P515_FINAL_HEADER_DEDUPE_V1"
if MARK in s:
    print("[OK] already patched")
    sys.exit(0)

snippet=r'''
# VSP_P515_FINAL_HEADER_DEDUPE_V1
# Final WSGI middleware: dedupe selected response headers (keep last) to satisfy audit/commercial polish.
class _VSPFinalHeaderDedupeV1:
    def __init__(self, app):
        self.app = app
        self.targets = set([
            "content-security-policy",
            "content-security-policy-report-only",
            "cross-origin-opener-policy",
            "cross-origin-resource-policy",
            "permissions-policy",
        ])

    def __call__(self, environ, start_response):
        def _sr(status, headers, exc_info=None):
            hdrs = list(headers or [])
            # keep last occurrence for target headers
            last = {}
            for i,(k,v) in enumerate(hdrs):
                lk = (k or "").lower()
                if lk in self.targets:
                    last[lk] = i
            out=[]
            for i,(k,v) in enumerate(hdrs):
                lk = (k or "").lower()
                if lk in self.targets and last.get(lk) != i:
                    continue
                out.append((k,v))
            start_response(status, out, exc_info)
        return self.app(environ, _sr)

def _vsp_p515_wrap_final(app_obj):
    try:
        if callable(app_obj):
            return _VSPFinalHeaderDedupeV1(app_obj)
    except Exception:
        pass
    return app_obj

try:
    if "application" in globals():
        globals()["application"] = _vsp_p515_wrap_final(globals()["application"])
    if "app" in globals() and callable(globals()["app"]):
        globals()["app"] = _vsp_p515_wrap_final(globals()["app"])
except Exception:
    pass
'''
p.write_text(s.rstrip()+"\n\n"+snippet+"\n", encoding="utf-8")
print("[OK] patched", p)
PY

python3 -m py_compile "$T" && echo "[OK] py_compile $T"
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== verify CSP lines =="
curl -sS -D- -o /dev/null "$BASE/c/dashboard" | awk 'BEGIN{IGNORECASE=1} /^Content-Security-Policy:/{print}'
