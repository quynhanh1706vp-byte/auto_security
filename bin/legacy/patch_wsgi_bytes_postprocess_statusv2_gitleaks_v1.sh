#!/usr/bin/env bash
set -euo pipefail
APP="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_wsgi_bytes_gitleaks_${TS}"
echo "[BACKUP] $APP.bak_wsgi_bytes_gitleaks_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1 ==="
if TAG in t:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# 1) Insert middleware class near the preempt middleware or near top
insert_pos = t.find("VSP_WSGI_PREEMPT_V1")
if insert_pos == -1:
    # fallback: after imports (first blank line after imports)
    m = re.search(r"(?s)\A.*?\n\n", t)
    insert_pos = m.end() if m else 0
else:
    # insert a bit before it to keep helper close
    insert_pos = max(0, insert_pos - 200)

middleware = r'''
class _VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1:
    """Outermost WSGI wrapper: mutate JSON bytes for /api/vsp/run_status_v2/* so fields can't be overwritten later."""
    # === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1 ===
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if "/api/vsp/run_status_v2/" not in path:
            return self.app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None, "body_via_write": []}

        def _start_response_cap(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            # WSGI write callable (rarely used by Flask/gunicorn, but handle anyway)
            def _write(data):
                try:
                    if data:
                        captured["body_via_write"].append(data)
                except Exception:
                    pass
            return _write

        it = self.app(environ, _start_response_cap)

        # Collect body bytes (small JSON payload)
        chunks = []
        try:
            if captured["body_via_write"]:
                chunks.extend(captured["body_via_write"])
            if it is not None:
                for c in it:
                    if c:
                        chunks.append(c)
        finally:
            try:
                close = getattr(it, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        body = b"".join(chunks)
        status = captured["status"] or "200 OK"
        headers = captured["headers"] or []

        # Only mutate if JSON
        ct = ""
        for k, v in headers:
            if str(k).lower() == "content-type":
                ct = str(v)
                break

        if ("application/json" not in ct.lower()) or (not body):
            start_response(status, headers, captured["exc"])
            return [body]

        try:
            import json
            from pathlib import Path as _P

            payload = json.loads(body.decode("utf-8", errors="ignore"))
            if isinstance(payload, dict):
                # Defaults (commercial: never null)
                if payload.get("overall_verdict", None) is None:
                    payload["overall_verdict"] = ""

                payload.setdefault("has_gitleaks", False)
                payload.setdefault("gitleaks_verdict", "")
                payload.setdefault("gitleaks_total", 0)
                payload.setdefault("gitleaks_counts", {})

                ci = payload.get("ci_run_dir") or payload.get("ci_dir") or payload.get("ci") or ""
                ci = str(ci).strip()
                if ci:
                    def _readj(fp):
                        try:
                            if fp and fp.exists():
                                return json.loads(fp.read_text(encoding="utf-8", errors="ignore") or "{}")
                        except Exception:
                            return None
                        return None

                    base = _P(ci)

                    # Gitleaks autodiscovery (canonical then rglob)
                    gsum = _readj(base / "gitleaks" / "gitleaks_summary.json") or _readj(base / "gitleaks_summary.json")
                    if not isinstance(gsum, dict):
                        try:
                            for fp in base.rglob("gitleaks_summary.json"):
                                gsum = _readj(fp)
                                if isinstance(gsum, dict):
                                    break
                        except Exception:
                            gsum = None

                    if isinstance(gsum, dict):
                        payload["has_gitleaks"] = True
                        payload["gitleaks_verdict"] = str(gsum.get("verdict") or "")
                        try:
                            payload["gitleaks_total"] = int(gsum.get("total") or 0)
                        except Exception:
                            payload["gitleaks_total"] = 0
                        cc = gsum.get("counts")
                        payload["gitleaks_counts"] = cc if isinstance(cc, dict) else {}

                    # Gate is source of truth for overall
                    gate = _readj(base / "run_gate_summary.json")
                    if isinstance(gate, dict):
                        payload["overall_verdict"] = str(gate.get("overall") or payload.get("overall_verdict") or "")

                new_body = json.dumps(payload, ensure_ascii=False).encode("utf-8")

                # fix content-length
                new_headers = []
                for k, v in headers:
                    if str(k).lower() == "content-length":
                        continue
                    new_headers.append((k, v))
                new_headers.append(("Content-Length", str(len(new_body))))

                start_response(status, new_headers, captured["exc"])
                return [new_body]
        except Exception:
            pass

        # fallback: return original
        start_response(status, headers, captured["exc"])
        return [body]
'''.strip("\n") + "\n\n"

t2 = t[:insert_pos] + "\n\n" + middleware + t[insert_pos:]

# 2) Install wrapper right AFTER the line that installs VSP_WSGI_PREEMPT_V1
# Look for: app.wsgi_app = ...VSP_WSGI_PREEMPT_V1...
pat = re.compile(r"(?m)^(?P<ind>\s*)app\.wsgi_app\s*=\s*.*VSP_WSGI_PREEMPT_V1.*$")
m = pat.search(t2)
if not m:
    raise SystemExit("[ERR] cannot find line installing VSP_WSGI_PREEMPT_V1 via app.wsgi_app = ...")

ind = m.group("ind")
install = "\n".join([
    f"{ind}# install outermost bytes postprocess for statusv2 (gitleaks + gate)",
    f"{ind}app.wsgi_app = _VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1(app.wsgi_app)",
    f"{ind}print('[VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1] installed')",
    ""
])

# insert right after that install line
eol = t2.find("\n", m.end())
t2 = t2[:eol+1] + install + t2[eol+1:]

p.write_text(t2, encoding="utf-8")
print("[OK] inserted WSGI bytes postprocess + installed wrapper")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile vsp_demo_app.py OK"
echo "DONE"
