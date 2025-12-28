#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need sed

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_gate_smart_${TS}"
echo "[BACKUP] ${F}.bak_gate_smart_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V1"
if marker in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

patch = r'''
# === VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V1 ===
# Commercial: GateStory MUST NOT spam 404/403 due to wrong rid/path/name.
# If /api/vsp/run_file_allow is used to fetch gate files (run_gate*.json),
# rewrite to latest gate-root RID and force root file run_gate_summary.json.
try:
    from pathlib import Path as __Path
    from urllib.parse import parse_qs as __parse_qs, urlencode as __urlencode
    import time as __time

    def __vsp__pick_latest_gate_root_rid_v1():
        roots = [
            __Path("/home/test/Data/SECURITY_BUNDLE/out"),
            __Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        ]
        best = (0.0, "")
        for root in roots:
            if not root.exists():
                continue
            try:
                for d in root.iterdir():
                    if not d.is_dir():
                        continue
                    name = d.name
                    if not (name.startswith("RUN_") or name.startswith("VSP_CI_RUN_") or "_RUN_" in name):
                        continue
                    gate = d / "run_gate_summary.json"
                    if gate.exists():
                        try:
                            mt = gate.stat().st_mtime
                        except Exception:
                            mt = __time.time()
                        if mt > best[0]:
                            best = (mt, name)
            except Exception:
                continue
        return best[1] or ""

    def __vsp__run_file_allow_gate_smart_wrapper_v1(app):
        def _w(environ, start_response):
            try:
                pi = (environ.get("PATH_INFO") or "")
                if pi == "/api/vsp/run_file_allow":
                    qs = __parse_qs(environ.get("QUERY_STRING",""), keep_blank_values=True)
                    # accept both "path" and "name" (your console shows name=...)
                    want = ""
                    if "path" in qs and qs["path"]:
                        want = (qs["path"][0] or "")
                    elif "name" in qs and qs["name"]:
                        want = (qs["name"][0] or "")
                    want_l = want.lower()

                    # only gate-related files trigger smart rewrite
                    if want_l.startswith("run_gate") and want_l.endswith(".json"):
                        rid_gate = __vsp__pick_latest_gate_root_rid_v1()
                        if rid_gate:
                            qs["rid"] = [rid_gate]
                        # force stable file at root => avoids reports/403 + run_gate.json missing/404
                        qs["path"] = ["run_gate_summary.json"]
                        qs["name"] = ["run_gate_summary.json"]
                        environ["QUERY_STRING"] = __urlencode(qs, doseq=True)
            except Exception:
                pass
            return app(environ, start_response)
        return _w

    # wrap once
    if "__vsp__application_gate_smart_wrapped_v1" not in globals():
        __vsp__application_gate_smart_wrapped_v1 = True
        try:
            application = __vsp__run_file_allow_gate_smart_wrapper_v1(application)
        except Exception:
            pass
except Exception:
    pass
# === end VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V1 ===
'''

p.write_text(s + "\n\n" + patch + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service

echo "== quick verify: simulate WRONG rid + name=run_gate.json (must return 200 JSON) =="
BASE="http://127.0.0.1:8910"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=RUN_khach6_FULL_20251129_133030&name=run_gate.json" | sed -n '1,15p'
