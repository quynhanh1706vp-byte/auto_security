#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wsgibytes_codeql_last_v2_${TS}"
echo "[BACKUP] $F.bak_wsgibytes_codeql_last_v2_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V2 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V2 ===
def _vsp__unwrap_one_wsgilayer(maybe_app):
    # Try to unwrap closures like our previous _vsp__wsgi_bytes_* wrapper.
    try:
        f = maybe_app.wsgi_app
        for _ in range(4):
            if not callable(f): break
            cl = getattr(f, "__closure__", None)
            if not cl: break
            inner = None
            for cell in cl:
                try:
                    v = cell.cell_contents
                except Exception:
                    continue
                # pick a callable that looks like wsgi(environ,start_response)
                if callable(v) and hasattr(v, "__code__") and v.__code__.co_argcount >= 2:
                    inner = v
                    break
            if inner is None: break
            # avoid infinite loop
            if inner is f: break
            f = inner
        maybe_app.wsgi_app = f
        try:
            print("[VSP_WSGI_UNWRAP] unwrapped to", getattr(f, "__name__", str(f)))
        except Exception:
            pass
        return True
    except Exception as e:
        try:
            print("[VSP_WSGI_UNWRAP][WARN]", e)
        except Exception:
            pass
        return False

def _vsp__inject_codeql_fields_statusv2_v2(data: dict):
    import os, json
    # force keys exist (never null)
    data["has_codeql"] = bool(data.get("has_codeql") or False)
    data["codeql_verdict"] = data.get("codeql_verdict") or None
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

    # 2) fallback from run_gate_summary.by_tool.CODEQL
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

def _vsp__wsgi_bytes_statusv2_codeql_last_v2(inner_app):
    import json
    def app2(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not path.startswith("/api/vsp/run_status_v2/"):
            return inner_app(environ, start_response)

        captured = {"status": None, "headers": None}
        chunks = []

        def _sr_capture(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            def _write(b):
                try:
                    if b:
                        chunks.append(b)
                except Exception:
                    pass
            return _write

        resp_iter = inner_app(environ, _sr_capture)
        try:
            for part in resp_iter:
                if part:
                    chunks.append(part)
        finally:
            try:
                if hasattr(resp_iter, "close"):
                    resp_iter.close()
            except Exception:
                pass

        body = b"".join(chunks)

        # only attempt rewrite for JSON object
        try:
            txt = body.decode("utf-8", errors="ignore").strip()
            if not txt.startswith("{"):
                # pass-through (but must call real start_response)
                start_response(captured["status"] or "200 OK", captured["headers"] or [])
                return [body]
            data = json.loads(txt)
            if not isinstance(data, dict):
                start_response(captured["status"] or "200 OK", captured["headers"] or [])
                return [body]
        except Exception:
            start_response(captured["status"] or "200 OK", captured["headers"] or [])
            return [body]

        try:
            data = _vsp__inject_codeql_fields_statusv2_v2(data)
            out = json.dumps(data, ensure_ascii=False).encode("utf-8")
        except Exception:
            start_response(captured["status"] or "200 OK", captured["headers"] or [])
            return [body]

        # rebuild headers, fix content-length
        hs = captured["headers"] or []
        new_h = []
        for (k, v) in hs:
            if str(k).lower() == "content-length":
                continue
            new_h.append((k, v))
        new_h.append(("Content-Length", str(len(out))))
        new_h.append(("X-VSP-WSGI-CODEQL", "1"))
        start_response(captured["status"] or "200 OK", new_h)
        return [out]
    return app2

try:
    # unwrap the buggy layer(s) we previously installed, then install fixed one
    _vsp__unwrap_one_wsgilayer(app)
    app.wsgi_app = _vsp__wsgi_bytes_statusv2_codeql_last_v2(app.wsgi_app)
    try:
        print("[VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V2] installed")
    except Exception:
        pass
except Exception as e:
    try:
        print("[VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_LAST_V2][WARN]", e)
    except Exception:
        pass
'''

p.write_text(t + "\n\n" + block + "\n", encoding="utf-8")
print("[OK] appended codeql LAST V2 (fix truncation)")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== VERIFY raw json validity =="
RID="RUN_VSP_CI_20251215_034956"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" > /tmp/v2_fixed.json
python3 - <<'PY'
import json
p="/tmp/v2_fixed.json"
s=open(p,"r",encoding="utf-8",errors="ignore").read()
json.loads(s)
print("[OK] json valid, bytes=", len(s))
PY

echo "== VERIFY fields =="
cat /tmp/v2_fixed.json | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict, gate_codeql:(.run_gate_summary.by_tool.CODEQL//null)}'
