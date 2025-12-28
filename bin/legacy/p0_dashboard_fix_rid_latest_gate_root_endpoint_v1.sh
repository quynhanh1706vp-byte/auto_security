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
cp -f "$WSGI" "${WSGI}.bak_rid_latest_gate_root_${TS}"
echo "[BACKUP] ${WSGI}.bak_rid_latest_gate_root_${TS}"

python3 - <<'PY'
from pathlib import Path
import time, re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RID_LATEST_GATE_ROOT_MW_V1"
if marker in s:
    print("[OK] marker already present:", marker)
    raise SystemExit(0)

addon = r'''
# ===================== VSP_P0_RID_LATEST_GATE_ROOT_MW_V1 =====================
# Provide endpoint expected by dashboard bundle:
#   GET /api/vsp/rid_latest_gate_root
# by internally calling existing handlers (/api/vsp/latest_rid, fallback /api/vsp/runs)
# without requiring Flask route edits (pure WSGI intercept).

def _vsp_p0__call_inner_wsgi(app, path, query_string=""):
    import json
    env2 = {}
    def _sr(status, headers, exc_info=None):
        env2["_status"] = status
        env2["_headers"] = headers
    # call inner app with a minimal env clone (will be merged from a real environ in MW)
    # this function will be called with a fully built environ in MW below.
    raise RuntimeError("should be patched by MW with real environ")

class VSPP0RidLatestGateRootMW:
    def __init__(self, app):
        self.app = app
        setattr(self, "__vsp_p0_rid_latest_gate_root_mw_v1__", True)

    def _call_inner(self, environ, path, query_string=""):
        import json
        # clone environ and force GET
        env2 = dict(environ)
        env2["REQUEST_METHOD"] = "GET"
        env2["PATH_INFO"] = path
        env2["QUERY_STRING"] = query_string or ""
        env2.pop("CONTENT_LENGTH", None)
        env2.pop("CONTENT_TYPE", None)

        captured = {"status": None, "headers": None}
        body_chunks = []

        def sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = headers

        it = self.app(env2, sr)
        try:
            for c in it:
                body_chunks.append(c)
        finally:
            if hasattr(it, "close"):
                try: it.close()
                except Exception: pass

        raw = b"".join(body_chunks)
        # best-effort json decode
        try:
            return captured["status"] or "200 OK", captured["headers"] or [], json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            return captured["status"] or "200 OK", captured["headers"] or [], {"_raw": raw.decode("utf-8", "replace")}

    def __call__(self, environ, start_response):
        import json, time, re

        path = environ.get("PATH_INFO") or ""
        if path in ("/api/vsp/rid_latest_gate_root", "/api/vsp/rid_latest_gate_root.json"):
            rid = None
            src = None

            # 1) preferred: /api/vsp/latest_rid
            try:
                _st, _hdr, j = self._call_inner(environ, "/api/vsp/latest_rid", "")
                rid = j.get("rid") or j.get("run_id") or j.get("id")
                if rid:
                    src = "/api/vsp/latest_rid"
            except Exception:
                rid = None

            # 2) fallback: /api/vsp/runs?limit=10  (pick first non-empty, prefer non RUN_*)
            if not rid:
                try:
                    _st, _hdr, j2 = self._call_inner(environ, "/api/vsp/runs", "limit=10")
                    runs = j2.get("runs") or j2.get("data") or j2.get("items") or []
                    cands = []
                    for r in runs:
                        if not isinstance(r, dict): 
                            continue
                        x = r.get("rid") or r.get("run_id") or r.get("id")
                        if x: cands.append(x)
                    # prefer VSP_* then RUN_*
                    for x in cands:
                        if isinstance(x, str) and x.startswith("VSP_"):
                            rid = x; break
                    if not rid and cands:
                        rid = cands[0]
                    if rid:
                        src = "/api/vsp/runs?limit=10"
                except Exception:
                    rid = None

            # build response: be generous with field names for JS compatibility
            gate_root = f"gate_root_{rid}" if rid else None
            out = {
                "ok": bool(rid),
                "rid": rid,
                "run_id": rid,
                "gate_root": gate_root,
                "gate_root_id": gate_root,
                "source": src,
                "ts": time.time(),
            }
            b = json.dumps(out, ensure_ascii=False).encode("utf-8")
            start_response("200 OK", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-store"),
                ("Content-Length", str(len(b))),
            ])
            return [b]

        return self.app(environ, start_response)

# Wrap exported WSGI callables if present (idempotent)
for _name in ("application", "app"):
    _obj = globals().get(_name)
    if callable(_obj) and not getattr(_obj, "__vsp_p0_rid_latest_gate_root_mw_v1__", False):
        globals()[_name] = VSPP0RidLatestGateRootMW(_obj)
# ===================== /VSP_P0_RID_LATEST_GATE_ROOT_MW_V1 =====================
'''
p.write_text(s + ("\n" if not s.endswith("\n") else "") + addon, encoding="utf-8")
print("[OK] appended MW:", marker)
PY

echo "== py_compile =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC"

echo "== verify endpoint =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 240; echo
echo "== done =="
echo "[DONE] Hard refresh: Ctrl+Shift+R  $BASE/vsp5"
