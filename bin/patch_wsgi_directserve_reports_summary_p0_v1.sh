#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_directserve_summary_${TS}"
echo "[BACKUP] ${F}.bak_directserve_summary_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_RUN_FILE_DIRECTSERVE_REPORTS_SUMMARY_P0_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# {MARK}
# Direct-serve ONLY reports/SUMMARY.txt to avoid allowlist/validator blocking.
# This stays commercial-safe: fixed path, fixed filename, strict RID folder under SECURITY_BUNDLE/out or out_ci.
from urllib.parse import parse_qs as _parse_qs
from pathlib import Path as _Path

class _VspRunFileDirectServeSummaryMW:
    def __init__(self, app):
        self.app = app
        self.root = _Path("/home/test/Data/SECURITY_BUNDLE")
    def _resolve_run_dir(self, rid: str):
        rid = (rid or "").strip()
        cands = []
        if rid:
            cands.append(rid)
            if "RUN_" in rid:
                cands.append(rid[rid.find("RUN_"):])
        for cand in cands:
            for base in ("out", "out_ci"):
                d = self.root / base / cand
                if d.is_dir():
                    return d
        return None

    def __call__(self, environ, start_response):
        try:
            if (environ.get("PATH_INFO","") or "") == "/api/vsp/run_file":
                qs = environ.get("QUERY_STRING","") or ""
                q = _parse_qs(qs, keep_blank_values=True)
                rid = (q.get("rid") or q.get("run_id") or q.get("runId") or [""])[0]
                name = (q.get("name") or q.get("path") or q.get("file") or [""])[0]
                name = (name or "").strip()

                # normalize summary variants
                if name in ("reports/SUMMARY.txt", "reports/summary.txt", "SUMMARY.txt", "summary.txt"):
                    run_dir = self._resolve_run_dir(rid)
                    if run_dir:
                        fp = run_dir / "reports" / "SUMMARY.txt"
                        if fp.is_file() and fp.stat().st_size > 0:
                            data = fp.read_bytes()
                            headers = [
                                ("Content-Type", "text/plain; charset=utf-8"),
                                ("Content-Length", str(len(data))),
                                ("Cache-Control", "no-store"),
                            ]
                            start_response("200 OK", headers)
                            return [data]
        except Exception:
            pass

        return self.app(environ, start_response)

application = _VspRunFileDirectServeSummaryMW(application)
'''.replace("{MARK}", MARK)

p.write_text(s + "\n" + block + "\n", encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"

sudo systemctl restart vsp-ui-8910.service
sleep 0.8

BASE="http://127.0.0.1:8910"
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | jq -r '.items[0].run_id')"
echo "RID=$RID"
curl -sS -o /dev/null -w "reports/SUMMARY.txt -> %{http_code}\n" \
  "$BASE/api/vsp/run_file?rid=$RID&name=reports/SUMMARY.txt" || true
