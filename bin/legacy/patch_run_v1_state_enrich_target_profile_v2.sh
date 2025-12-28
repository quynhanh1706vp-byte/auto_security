#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_enrich_v2_${TS}"
echo "[BACKUP] $F.bak_enrich_v2_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_ENRICH_STATEFILE_V2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

helper = f'''
# === {MARK} ===
def _vsp_enrich_statefile_v2(req_id, req_payload):
    try:
        from pathlib import Path
        import json, time
        # ui/out_ci/ui_req_state/<RID>.json
        ui_root = Path(__file__).resolve().parents[1]
        st = ui_root / "out_ci" / "ui_req_state" / f"{req_id}.json"
        if not st.is_file():
            return
        data = json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{{}}")
        if not isinstance(data, dict):
            data = {{}}
        # backfill contract fields
        for k in ("target","profile","mode","target_type"):
            if (not data.get(k)) and (req_payload.get(k) is not None):
                data[k] = req_payload.get(k) or ""
        # store minimal payload for later heuristics/debug
        rp = data.get("req_payload")
        if not isinstance(rp, dict):
            rp = {{}}
        for k in ("mode","profile","target_type","target"):
            if k in req_payload:
                rp[k] = req_payload.get(k)
        data["req_payload"] = rp
        data["last_enrich_ts"] = int(time.time())
        st.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        return
# === END {MARK} ===
'''

# insert helper after imports (best effort)
m = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
if m:
    insert_pos = m.end()
    txt = txt[:insert_pos] + helper + "\n" + txt[insert_pos:]
else:
    txt = helper + "\n" + txt

# inject call inside run_v1: before returning jsonify that contains request_id
# We re-parse payload safely here (no dependence on variable names in file).
call = f"""
    # === {MARK} CALL ===
    try:
        _req_payload = request.get_json(silent=True) or {{}}
    except Exception:
        _req_payload = {{}}
    try:
        _vsp_enrich_statefile_v2(request_id, _req_payload)
    except Exception:
        pass
    # === END {MARK} CALL ===
"""

# find a return jsonify containing request_id
pat = r"(\n\s*return\s+jsonify\([\s\S]{0,400}?request_id[\s\S]{0,400}?\)\s*)"
m2 = re.search(pat, txt, flags=re.M)
if not m2:
    # fallback: any "return jsonify(" inside run_v1
    m2 = re.search(r"(\n\s*def\s+run_v1\s*\([\s\S]{0,2000}?)(\n\s*return\s+jsonify\()", txt, flags=re.M)
    if not m2:
        raise SystemExit("[ERR] cannot find return jsonify(...) to hook in run_v1")
    # insert call just before that return
    txt = txt[:m2.start(2)] + call + "\n" + txt[m2.start(2):]
else:
    # insert call right before that return
    txt = txt[:m2.start(1)] + call + "\n" + txt[m2.start(1):]

p.write_text(txt, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
