#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_gate_smart_v3_${TS}"
echo "[BACKUP] ${F}.bak_gate_smart_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V3"
if marker in s:
    print("[SKIP] already patched V3")
    raise SystemExit(0)

patch = r'''
# === VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V3 ===
# Strongly prefer VSP_CI_RUN + gate_root + non-UNKNOWN + non-backfilled/non-degraded.
try:
    import json as __json
    from pathlib import Path as __Path
    import time as __time

    def __vsp__pick_latest_gate_root_rid_v3():
        roots = [
            __Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
            __Path("/home/test/Data/SECURITY_BUNDLE/out"),
        ]
        # score tuple (is_ci, gate_root, overall_known, not_degraded, not_backfilled, mtime)
        best = (-1, -1, -1, -1, -1, 0.0, "")
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

                    gate_root_path = d / "run_gate_summary.json"
                    gate_rep_path  = d / "reports" / "run_gate_summary.json"

                    gate_path = None
                    gate_root = 0
                    if gate_root_path.exists():
                        gate_path = gate_root_path
                        gate_root = 1
                    elif gate_rep_path.exists():
                        gate_path = gate_rep_path
                        gate_root = 0
                    else:
                        continue

                    try:
                        mt = gate_path.stat().st_mtime
                    except Exception:
                        mt = __time.time()

                    is_ci = 1 if name.startswith("VSP_CI_RUN_") else 0

                    overall_known = 0
                    not_degraded = 1
                    not_backfilled = 1

                    try:
                        obj = __json.loads(gate_path.read_text(encoding="utf-8", errors="replace"))
                        ov = str(obj.get("overall","")).upper().strip()
                        vd = str(obj.get("verdict","")).upper().strip()
                        if ov and ov != "UNKNOWN" and vd and vd != "UNKNOWN":
                            overall_known = 1
                        if bool(obj.get("degraded", False)) is True:
                            not_degraded = 0
                        note = str(obj.get("note","") or "")
                        if "Backfilled minimal reports" in note or "no report artifacts" in note:
                            not_backfilled = 0
                    except Exception:
                        # if unreadable => treat as weak
                        overall_known = 0
                        not_degraded = 0
                        not_backfilled = 0

                    cand = (is_ci, gate_root, overall_known, not_degraded, not_backfilled, mt, name)
                    if cand > best:
                        best = cand
            except Exception:
                continue
        return best[-1] or ""

    # Replace v1 picker used by the V1 wrapper
    __vsp__pick_latest_gate_root_rid_v1 = __vsp__pick_latest_gate_root_rid_v3
except Exception:
    pass
# === end VSP_P1_RUN_FILE_ALLOW_GATE_SMART_V3 ===
'''

p.write_text(s + "\n\n" + patch + "\n", encoding="utf-8")
print("[OK] appended:", marker)
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

echo "== restart =="
sudo systemctl restart vsp-ui-8910.service

echo "== verify (must prefer VSP_CI_RUN... if exists) =="
BASE="http://127.0.0.1:8910"
curl -sS "$BASE/api/vsp/run_file_allow?rid=RUN_khach6_FULL_20251129_133030&name=run_gate.json" | head -n 12
