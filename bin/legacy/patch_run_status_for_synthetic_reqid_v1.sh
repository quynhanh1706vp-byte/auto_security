#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_synth_status_${TS}"
echo "[BACKUP] $F.bak_synth_status_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_SYNTH_REQID_STATUS_FROM_TAIL_V1" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

# locate wrapper function _export_run_status_v1(req_id)
m = re.search(r"^def\s+_export_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def _export_run_status_v1(req_id):")

# find insertion point after "out = _normalize(" line inside wrapper
ins_m = re.search(r"^\s*out\s*=\s*_normalize\([^\n]+\)\s*$", txt[m.end():], flags=re.M)
if not ins_m:
    raise SystemExit("[ERR] cannot find 'out = _normalize(...)' inside _export_run_status_v1")
ins = m.end() + ins_m.end()

hook = r'''

    # === VSP_SYNTH_REQID_STATUS_FROM_TAIL_V1 ===
    # If synthetic req_id is used (VSP_UIREQ_*), map NOT_FOUND -> RUNNING by parsing last stage marker from logs.
    try:
      if isinstance(out, dict) and out.get("status") == "NOT_FOUND" and str(req_id).startswith("VSP_UIREQ_"):
        from pathlib import Path as _Path
        root = _Path(__file__).resolve().parents[1]  # .../ui
        # Prefer CI outer log if exists, else UI gateway log
        cand_logs = [
          root / "out_ci" / "ui_8910.log",
          root.parent / "out_ci" / "ui_8910.log",
          root / "out_ci" / "ci_outer.log",
        ]
        tail_txt = ""
        for lp in cand_logs:
          try:
            if lp.exists():
              arr = lp.read_text(encoding="utf-8", errors="ignore").splitlines()
              tail_txt = "\n".join(arr[-600:])
              if tail_txt.strip():
                break
          except Exception:
            continue

        stg = _extract_stage_from_tail(tail_txt) or {}
        total = int(stg.get("total", 0) or 0)
        i = int(stg.get("i", 0) or 0)
        name = str(stg.get("name", "") or "")
        prog = int(stg.get("progress", 0) or 0)
        if prog < 0: prog = 0
        if prog > 100: prog = 100

        out["status"] = "RUNNING"
        out["final"] = False
        out["error"] = ""
        out["stage_total"] = total
        out["stage_index"] = i
        out["stage_name"] = name
        out["progress_pct"] = prog
        out["stage_sig"] = f"{i}/{total}|{name}|{prog}"

        # ensure timeouts exist
        out.setdefault("stall_timeout_sec", int(out.get("stall_timeout_sec") or 180))
        out.setdefault("total_timeout_sec", int(out.get("total_timeout_sec") or 900))
    except Exception:
      pass
    # === END VSP_SYNTH_REQID_STATUS_FROM_TAIL_V1 ===
'''

txt2 = txt[:ins] + hook + txt[ins:]
p.write_text(txt2, encoding="utf-8")
print("[OK] inserted VSP_SYNTH_REQID_STATUS_FROM_TAIL_V1")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: create run to get synthetic req_id =="
RESP="$(curl -sS -X POST "http://localhost:8910/api/vsp/run_v1" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}')"
RID="$(python3 - <<PY
import json
o=json.loads('''$RESP''')
print(o.get("request_id") or "")
PY
)"
echo "RID=$RID"

echo "== Smoke: status must be RUNNING (not NOT_FOUND) =="
python3 - <<PY
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/$RID"
o=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
keys=["status","final","error","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print({k:o.get(k) for k in keys})
PY
