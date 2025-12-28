#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_enrich_mw_v5_${TS}"
echo "[BACKUP] ${F}.bak_runs_enrich_mw_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_ENRICH_WSGI_MW_V5"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P1_RUNS_ENRICH_WSGI_MW_V5 ---
# True WSGI middleware for /api/vsp/runs that works even if the app returns iterable bytes (not Werkzeug Response).
try:
    import json as _v5_json
    from pathlib import Path as _V5Path
except Exception:
    _v5_json = None
    _V5Path = None

def _v5_runs_enrich(data):
    try:
        if _V5Path is None:
            return data
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            return data

        roots = list(data.get("roots_used") or [])
        # include ui/out_ci if missing (you already had it sometimes)
        extra = ["/home/test/Data/SECURITY_BUNDLE/ui/out_ci", "/home/test/Data/SECURITY_BUNDLE/out_ci"]
        for r in extra:
            if r not in roots:
                roots.append(r)

        gate_candidates = [
            "run_gate_summary.json",
            "reports/run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate.json",
        ]
        findings_candidates = [
            "reports/findings_unified.json",
            "findings_unified.json",
        ]

        def find_run_dir(rid: str):
            for root in roots:
                if not root:
                    continue
                cand = _V5Path(root) / rid
                if cand.exists():
                    return cand
            return None

        rid_latest_gate = None
        rid_latest_findings = None

        for it in data["items"]:
            if not isinstance(it, dict):
                continue
            rid = it.get("run_id")
            if not rid:
                continue

            rd = find_run_dir(rid)
            has_gate = False
            has_findings = False
            if rd is not None:
                for rel in gate_candidates:
                    if (rd / rel).exists():
                        has_gate = True
                        break
                for rel in findings_candidates:
                    if (rd / rel).exists():
                        has_findings = True
                        break

            it.setdefault("has", {})
            it["has"]["gate"] = bool(has_gate)
            it["has"]["findings"] = bool(has_findings)

            if rid_latest_gate is None and has_gate:
                rid_latest_gate = rid
            if rid_latest_findings is None and has_findings:
                rid_latest_findings = rid

        data["rid_latest_gate"] = rid_latest_gate
        data["rid_latest_findings"] = rid_latest_findings
        data["rid_latest"] = rid_latest_gate or rid_latest_findings or data.get("rid_latest")
        return data
    except Exception:
        return data

try:
    _v5_inner_app = application  # type: ignore[name-defined]

    def application(environ, start_response):  # noqa: F811
        path = (environ or {}).get("PATH_INFO", "")
        if path != "/api/vsp/runs" or _v5_json is None:
            return _v5_inner_app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            # DO NOT call real start_response yet
            return None

        resp_iter = _v5_inner_app(environ, _sr)

        # buffer body (runs payload is small; still cap)
        buf = bytearray()
        cap = 3_000_000
        try:
            for chunk in resp_iter:
                if chunk:
                    buf += chunk
                if len(buf) > cap:
                    break
        finally:
            try:
                close = getattr(resp_iter, "close", None)
                if callable(close):
                    close()
            except Exception:
                pass

        # if too big or no captured headers -> fallback passthrough (but we already buffered)
        status = captured["status"] or "200 OK"
        headers = captured["headers"] or [("Content-Type", "application/json; charset=utf-8")]

        body_bytes = bytes(buf)
        try:
            data = _v5_json.loads(body_bytes.decode("utf-8", errors="replace"))
            data2 = _v5_runs_enrich(data)
            out = _v5_json.dumps(data2, ensure_ascii=False).encode("utf-8")
            # update headers
            # remove old content-length
            headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(out))))
            headers.append(("X-VSP-RUNS-ENRICH", "V5"))
            start_response(status, headers, captured["exc"])
            return [out]
        except Exception:
            # fallback: return original buffered body
            headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(body_bytes))))
            headers.append(("X-VSP-RUNS-ENRICH", "V5_FAILSAFE"))
            start_response(status, headers, captured["exc"])
            return [body_bytes]
except Exception:
    pass
""").strip() + "\n"

p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service

BASE=http://127.0.0.1:8910
echo "== HEAD /api/vsp/runs (must include X-VSP-RUNS-ENRICH: V5) =="
curl -sS -I "$BASE/api/vsp/runs?limit=2" | sed -n '1,30p'

echo
echo "== BODY /api/vsp/runs?limit=2 (must include rid_latest_gate/findings + item.has.gate/findings) =="
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 1800; echo
