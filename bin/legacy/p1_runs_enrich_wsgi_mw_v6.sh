#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_enrich_mw_v6_${TS}"
echo "[BACKUP] ${F}.bak_runs_enrich_mw_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_ENRICH_WSGI_MW_V6"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

block = textwrap.dedent(r"""
# --- VSP_P1_RUNS_ENRICH_WSGI_MW_V6 ---
# Tighten has.gate: true only if gate JSON is parseable (and prefer root gate files).
try:
    import json as _v6_json
    from pathlib import Path as _V6Path
except Exception:
    _v6_json = None
    _V6Path = None

def _v6_gate_parse_ok(fp: "_V6Path"):
    try:
        if _v6_json is None:
            return False, None
        if not fp.exists() or not fp.is_file():
            return False, None
        # cap read (2MB)
        b = fp.read_bytes()
        if len(b) > 2_000_000:
            return False, str(fp)
        obj = _v6_json.loads(b.decode("utf-8", errors="replace"))
        if not isinstance(obj, dict):
            return False, str(fp)
        # heuristic: gate json should have at least one of these keys
        if not (("overall" in obj) or ("overall_status" in obj) or ("by_type" in obj) or ("verdict" in obj)):
            # still JSON but not gate-ish
            return False, str(fp)
        return True, str(fp)
    except Exception:
        return False, str(fp)

def _v6_runs_enrich(data):
    try:
        if _V6Path is None:
            return data
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            return data

        roots = list(data.get("roots_used") or [])
        extra = ["/home/test/Data/SECURITY_BUNDLE/ui/out_ci", "/home/test/Data/SECURITY_BUNDLE/out_ci"]
        for r in extra:
            if r not in roots:
                roots.append(r)

        # prefer root first (avoid reports-only until run_file_allow is smart-fallback)
        gate_candidates = [
            "run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate_summary.json",
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
                cand = _V6Path(root) / rid
                if cand.exists():
                    return cand
            return None

        rid_latest_gate_root = None
        rid_latest_gate_any = None
        rid_latest_findings = None

        for it in data["items"]:
            if not isinstance(it, dict):
                continue
            rid = it.get("run_id")
            if not rid:
                continue
            rd = find_run_dir(rid)

            has_findings = False
            has_gate = False
            has_gate_root = False
            gate_src = None

            if rd is not None:
                # findings existence
                for rel in findings_candidates:
                    if (rd / rel).exists():
                        has_findings = True
                        break

                # gate parse check
                for rel in gate_candidates:
                    fp = rd / rel
                    ok, src = _v6_gate_parse_ok(fp)
                    if ok:
                        has_gate = True
                        gate_src = rel
                        has_gate_root = (not rel.startswith("reports/"))
                        break

            it.setdefault("has", {})
            it["has"]["findings"] = bool(has_findings)
            it["has"]["gate"] = bool(has_gate)
            it["has"]["gate_root"] = bool(has_gate_root)
            if gate_src:
                it["has"]["gate_source"] = gate_src

            if rid_latest_findings is None and has_findings:
                rid_latest_findings = rid
            if has_gate_root and rid_latest_gate_root is None:
                rid_latest_gate_root = rid
            if has_gate and rid_latest_gate_any is None:
                rid_latest_gate_any = rid

        data["rid_latest_gate_root"] = rid_latest_gate_root
        data["rid_latest_gate"] = rid_latest_gate_root or rid_latest_gate_any
        data["rid_latest_findings"] = rid_latest_findings
        data["rid_latest"] = data["rid_latest_gate"] or rid_latest_findings or data.get("rid_latest")
        return data
    except Exception:
        return data

try:
    _v6_inner_app = application  # type: ignore[name-defined]
    def application(environ, start_response):  # noqa: F811
        path = (environ or {}).get("PATH_INFO", "")
        if path != "/api/vsp/runs" or _v6_json is None:
            return _v6_inner_app(environ, start_response)

        captured = {"status": None, "headers": None, "exc": None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = list(headers or [])
            captured["exc"] = exc_info
            return None

        resp_iter = _v6_inner_app(environ, _sr)

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

        status = captured["status"] or "200 OK"
        headers = captured["headers"] or [("Content-Type", "application/json; charset=utf-8")]
        body_bytes = bytes(buf)

        try:
            data = _v6_json.loads(body_bytes.decode("utf-8", errors="replace"))
            data2 = _v6_runs_enrich(data)
            out = _v6_json.dumps(data2, ensure_ascii=False).encode("utf-8")
            headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(out))))
            # override/replace enrich header
            headers = [(k, v) for (k, v) in headers if k.lower() != "x-vsp-runs-enrich"]
            headers.append(("X-VSP-RUNS-ENRICH", "V6"))
            start_response(status, headers, captured["exc"])
            return [out]
        except Exception:
            headers = [(k, v) for (k, v) in headers if k.lower() != "content-length"]
            headers.append(("Content-Length", str(len(body_bytes))))
            headers = [(k, v) for (k, v) in headers if k.lower() != "x-vsp-runs-enrich"]
            headers.append(("X-VSP-RUNS-ENRICH", "V6_FAILSAFE"))
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
echo "== HEAD /api/vsp/runs (expect X-VSP-RUNS-ENRICH: V6) =="
curl -sS -I "$BASE/api/vsp/runs?limit=2" | sed -n '1,35p'
echo
echo "== BODY /api/vsp/runs?limit=2 (expect rid_latest_gate_root + gate_source) =="
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 2000; echo
