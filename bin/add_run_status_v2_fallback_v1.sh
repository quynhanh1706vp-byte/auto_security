#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

# quick skip if already exists
if grep -qE "route\(\s*['\"]/api/vsp/run_status_v2/<" "$F"; then
  echo "[OK] run_status_v2 route already exists, skip"
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_add_runstatusv2_${TS}"
echo "[BACKUP] $F.bak_add_runstatusv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")
TAG = "# === VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

# anchor: insert right after api_vsp_run_status(req_id) function (exists in your file at ~2706)
m = re.search(r'(?ms)^def\s+api_vsp_run_status\s*\(\s*req_id\s*\)\s*:\s*.*?\n(?=^\S)', t)
if not m:
    raise SystemExit("[ERR] cannot find def api_vsp_run_status(req_id) block to anchor insert")

block_end = m.end()

inject = r'''
''' + TAG + r'''
# Commercial contract: NEVER 404 for /api/vsp/run_status_v2/<RID>
# Provide fallback v2 endpoint that:
#  - resolves ci_run_dir via _vsp_guess_ci_run_dir_from_rid_v33
#  - extracts stage info from CI runner.log tail (best-effort)
#  - injects KICS summary if present
try:
    from flask import request as _rq
    @app.route("/api/vsp/run_status_v2/<rid>", methods=["GET"])
    def api_vsp_run_status_v2(rid):
        import json as _json
        from pathlib import Path as _Path
        from flask import jsonify as _jsonify

        _rid = (rid or "").split("?", 1)[0].strip()
        _rid_norm = _rid[4:].strip() if _rid.startswith("RUN_") else _rid

        # defaults (must not crash UI)
        payload = {
            "ok": True,
            "status": "RUNNING",
            "final": False,
            "error": "",
            "http_code": 200,
            "progress_pct": 0,
            "stage_index": 0,
            "stage_total": 0,
            "stage_name": "",
            "stage_sig": "",
            "stall_timeout_sec": 600,
            "total_timeout_sec": 7200,
            "ci_run_dir": None,
            "kics_verdict": "",
            "kics_total": 0,
            "kics_counts": {},
        }

        # try env overrides if helpers exist
        try:
            _stall = globals().get("_vsp_env_int")
            if callable(_stall):
                payload["stall_timeout_sec"] = int(_stall("VSP_UIREQ_STALL_TIMEOUT_SEC", _stall("VSP_STALL_TIMEOUT_SEC", 600)))
                payload["total_timeout_sec"] = int(_stall("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _stall("VSP_TOTAL_TIMEOUT_SEC", 7200)))
        except Exception:
            pass

        # resolve ci dir
        ci = ""
        try:
            _guess = globals().get("_vsp_guess_ci_run_dir_from_rid_v33")
            if callable(_guess):
                ci = _guess(_rid_norm) or ""
        except Exception:
            ci = ""

        if not ci:
            payload["ok"] = False
            payload["status"] = "ERROR"
            payload["final"] = True
            payload["http_code"] = 404
            payload["error"] = "CI_RUN_DIR_NOT_FOUND"
            return _jsonify(payload), 200

        payload["ci_run_dir"] = ci

        # parse stage from CI logs best-effort
        try:
            ciP = _Path(ci)
            cand_logs = [
                ciP / "runner.log",
                ciP / "outer_runner.log",
                ciP / "run.log",
            ]
            logp = next((x for x in cand_logs if x.is_file()), None)
            if logp:
                # tail lines
                _tail = globals().get("_vsp_tail_lines")
                _parse = globals().get("_vsp_parse_status_from_log")
                _lines = []
                if callable(_tail):
                    _lines = _tail(str(logp), n=220) or []
                else:
                    _lines = (logp.read_text(encoding="utf-8", errors="ignore").splitlines()[-220:])

                # stage marker: ===== [3/8] KICS (EXT) =====
                st_re = re.compile(r'\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]')
                stage_i = stage_t = 0
                stage_n = ""
                for ln in reversed(_lines):
                    m2 = st_re.search(ln)
                    if m2:
                        stage_i = int(m2.group(1))
                        stage_t = int(m2.group(2))
                        stage_n = (m2.group(3) or "").strip()
                        break

                if stage_t > 0:
                    payload["stage_index"] = stage_i
                    payload["stage_total"] = stage_t
                    payload["stage_name"] = stage_n
                    payload["stage_sig"] = stage_n
                    try:
                        payload["progress_pct"] = int((stage_i / max(stage_t, 1)) * 100)
                    except Exception:
                        payload["progress_pct"] = 0

                # overall status parse (if available)
                if callable(_parse):
                    try:
                        st, _ci_run_id, gate, final_rc = _parse(_lines)
                        if st:
                            payload["status"] = st
                        # if parser gives final_rc, treat as final
                        if final_rc is not None and str(final_rc).strip() != "":
                            payload["final"] = True
                    except Exception:
                        pass
        except Exception:
            pass

        # inject kics summary
        try:
            ks = _Path(ci) / "kics" / "kics_summary.json"
            if ks.is_file():
                jo = _json.loads(ks.read_text(encoding="utf-8", errors="ignore") or "{}")
                if isinstance(jo, dict):
                    payload["kics_verdict"] = str(jo.get("verdict") or "")
                    try:
                        payload["kics_total"] = int(jo.get("total") or 0)
                    except Exception:
                        pass
                    cc = jo.get("counts")
                    payload["kics_counts"] = cc if isinstance(cc, dict) else {}
        except Exception:
            pass

        return _jsonify(payload), 200
except Exception:
    pass
''' + "\n"

# inject after api_vsp_run_status block
t2 = t[:block_end] + inject + t[block_end:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted v2 fallback route after api_vsp_run_status")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ok,http_code,error,ci_run_dir,stage_name,stage_index,stage_total,progress_pct,kics_verdict,kics_total,kics_counts}'
