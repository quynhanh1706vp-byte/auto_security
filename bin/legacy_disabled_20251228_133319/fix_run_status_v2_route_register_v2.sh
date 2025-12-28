#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_runstatusv2_route_${TS}"
echo "[BACKUP] $F.bak_fix_runstatusv2_route_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

F = Path("vsp_demo_app.py")
t = F.read_text(encoding="utf-8", errors="ignore")

TAG_OLD = "# === VSP_ADD_RUN_STATUS_V2_FALLBACK_V1 ==="
TAG_NEW = "# === VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ==="
END_NEW = "# === END VSP_ADD_RUN_STATUS_V2_FALLBACK_WINLAST_V2 ==="

# 1) remove old injected block (best-effort) if exists
if TAG_OLD in t:
    # cut from old tag until a strong next anchor (JSON err handlers or RUN_API_FALLBACK or end)
    anchors = [
        "# === VSP_JSON_ERRHANDLERS",
        "# === VSP_RUN_API_FALLBACK",
        "app.register_error_handler(",
    ]
    idx0 = t.find(TAG_OLD)
    idx1 = None
    for a in anchors:
        j = t.find(a, idx0 + 1)
        if j != -1:
            idx1 = j
            break
    if idx1 is None:
        idx1 = idx0 + len(TAG_OLD)
    t = t[:idx0] + "\n" + t[idx1:]
    print("[OK] removed old v1 injected block")

# 2) remove previous WINLAST_V2 block if already present (idempotent)
if TAG_NEW in t and END_NEW in t:
    t = re.sub(r'(?ms)^[ \t]*' + re.escape(TAG_NEW) + r'.*?^[ \t]*' + re.escape(END_NEW) + r'\s*', '', t)
    print("[OK] removed previous WINLAST_V2 block for clean re-add")

# 3) append new route at file end (global scope, always executes at import)
inject = f"""
{TAG_NEW}
# Commercial contract: NEVER 404 for /api/vsp/run_status_v2/<RID>
try:
    from flask import jsonify as _jsonify

    @app.route("/api/vsp/run_status_v2/<rid>", methods=["GET"])
    def api_vsp_run_status_v2(rid):
        import json as _json
        import re as _re
        from pathlib import Path as _Path

        _rid = (rid or "").split("?", 1)[0].strip()
        _rid_norm = _rid[4:].strip() if _rid.startswith("RUN_") else _rid

        payload = {{
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
            "kics_counts": {{}},
        }}

        # resolve CI dir
        ci = ""
        try:
            _guess = globals().get("_vsp_guess_ci_run_dir_from_rid_v33")
            if callable(_guess):
                ci = (_guess(_rid_norm) or "").strip()
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

        # stage best-effort from runner.log (optional)
        try:
            ciP = _Path(ci)
            logp = None
            for nm in ("runner.log", "outer_runner.log", "run.log"):
                fp = ciP / nm
                if fp.is_file():
                    logp = fp
                    break
            if logp:
                try:
                    _tail = globals().get("_vsp_tail_lines")
                    if callable(_tail):
                        _lines = _tail(str(logp), n=260) or []
                    else:
                        _lines = logp.read_text(encoding="utf-8", errors="ignore").splitlines()[-260:]
                except Exception:
                    _lines = []

                st_re = _re.compile(r"\\[\\s*(\\d+)\\s*/\\s*(\\d+)\\s*\\]\\s*([^\\]]+?)\\s*\\]+", _re.I)
                for ln in reversed(_lines):
                    m = st_re.search(ln)
                    if m:
                        si = int(m.group(1)); st = int(m.group(2)); sn = (m.group(3) or "").strip()
                        payload["stage_index"] = si
                        payload["stage_total"] = st
                        payload["stage_name"]  = sn
                        payload["stage_sig"]   = sn
                        try:
                            payload["progress_pct"] = int((si / max(st, 1)) * 100)
                        except Exception:
                            payload["progress_pct"] = 0
                        break
        except Exception:
            pass

        # inject KICS summary
        try:
            ks = _Path(ci) / "kics" / "kics_summary.json"
            if ks.is_file():
                jo = _json.loads(ks.read_text(encoding="utf-8", errors="ignore") or "{{}}")
                if isinstance(jo, dict):
                    payload["kics_verdict"] = str(jo.get("verdict") or "")
                    try:
                        payload["kics_total"] = int(jo.get("total") or 0)
                    except Exception:
                        pass
                    cc = jo.get("counts")
                    payload["kics_counts"] = cc if isinstance(cc, dict) else {{}}
        except Exception:
            pass

        return _jsonify(payload), 200

except Exception:
    # Never break app import
    pass
{END_NEW}
"""

t = t.rstrip() + "\n\n" + inject + "\n"
F.write_text(t, encoding="utf-8")
print("[OK] appended WINLAST_V2 route at EOF")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] v2 route must NOT 404 handler anymore =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ok,http_code,error,ci_run_dir,stage_name,stage_index,stage_total,progress_pct,kics_verdict,kics_total,kics_counts}'
