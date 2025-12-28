#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wsgibytes_codeql_last_${TS}"
echo "[BACKUP] $F.bak_wsgibytes_codeql_last_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V1 ===
def _vsp__inject_codeql_fields_statusv2(data: dict):
    import os, json
    # force keys exist (never null)
    data["has_codeql"] = False if data.get("has_codeql") in (None, False, "null") else bool(data.get("has_codeql"))
    data["codeql_verdict"] = None if data.get("codeql_verdict") in ("null", "") else data.get("codeql_verdict")
    try:
        data["codeql_total"] = int(data.get("codeql_total") or 0)
    except Exception:
        data["codeql_total"] = 0

    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or ""
    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    # 1) prefer real summary
    try:
        if summary and os.path.isfile(summary):
            try:
                j = json.load(open(summary, "r", encoding="utf-8"))
            except Exception:
                j = {}
            data["has_codeql"] = True
            data["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict") or "AMBER"
            try:
                data["codeql_total"] = int(j.get("total") or 0)
            except Exception:
                data["codeql_total"] = 0
            return data
    except Exception:
        pass

    # 2) fallback from run_gate_summary.by_tool.CODEQL (you already have this in payload)
    try:
        rg = data.get("run_gate_summary") or {}
        bt = (rg.get("by_tool") or {})
        cq = bt.get("CODEQL") or bt.get("CodeQL") or {}
        if isinstance(cq, dict) and cq:
            data["has_codeql"] = True
            data["codeql_verdict"] = cq.get("verdict") or "AMBER"
            try:
                data["codeql_total"] = int(cq.get("total") or 0)
            except Exception:
                data["codeql_total"] = 0
            return data
    except Exception:
        pass

    # 3) fallback sarif presence
    try:
        if codeql_dir and os.path.isdir(codeql_dir):
            sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
            if sarifs:
                data["has_codeql"] = True
                data["codeql_verdict"] = data.get("codeql_verdict") or "AMBER"
    except Exception:
        pass

    return data

def _vsp__wsgi_bytes_statusv2_codeql_last_v1(inner_app):
    import json
    def app(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return inner_app(environ, start_response)

        status_box = {"status": None, "headers": None}
        def _sr(status, headers, exc_info=None):
            status_box["status"] = status
            status_box["headers"] = list(headers or [])
            return start_response(status, headers, exc_info)

        resp_iter = inner_app(environ, _sr)
        try:
            body = b"".join(resp_iter)
        finally:
            try:
                if hasattr(resp_iter, "close"):
                    resp_iter.close()
            except Exception:
                pass

        # only attempt json object bodies
        try:
            txt = body.decode("utf-8", errors="ignore").strip()
            if not txt.startswith("{"):
                return [body]
            data = json.loads(txt)
            if not isinstance(data, dict):
                return [body]
        except Exception:
            return [body]

        try:
            data = _vsp__inject_codeql_fields_statusv2(data)
            out = json.dumps(data, ensure_ascii=False).encode("utf-8")
        except Exception:
            return [body]

        # fix Content-Length header (if present)
        try:
            hs = status_box.get("headers") or []
            new_h = []
            for (k, v) in hs:
                if str(k).lower() == "content-length":
                    continue
                new_h.append((k, v))
            new_h.append(("Content-Length", str(len(out))))
            # re-send headers with same status
            start_response(status_box.get("status") or "200 OK", new_h)
        except Exception:
            # if header rewrite fails, just return out
            pass

        return [out]
    return app

try:
    app.wsgi_app = _vsp__wsgi_bytes_statusv2_codeql_last_v1(app.wsgi_app)
    try:
        print("[VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V1] installed")
    except Exception:
        pass
except Exception as e:
    try:
        print("[VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V1][WARN]", e)
    except Exception:
        pass
'''

p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended status_v2 codeql LAST wsgi-bytes postprocess")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== VERIFY =="
RID="RUN_VSP_CI_20251215_034956"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" \
 | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict, gate_codeql:(.run_gate_summary.by_tool.CODEQL//null)}'
