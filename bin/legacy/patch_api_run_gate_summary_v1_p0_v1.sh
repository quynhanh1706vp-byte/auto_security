#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

PY="vsp_demo_app.py"
[ -f "$PY" ] || { echo "[ERR] missing $PY (expected /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py)"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$PY" "$PY.bak_gate_summary_v1_${TS}"
echo "[BACKUP] $PY.bak_gate_summary_v1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

BLOCK = r'''
# =========================
# P0: Canonical Gate Summary (run_gate_summary_v1)
# - Always HTTP 200 (UI-friendly), with ok flag + overall status
# - Reads run_gate_summary*.json in RUN_DIR if present
# - Fallback derives minimal overall from findings_unified.json
# =========================
from pathlib import Path as _Path
import os as _os, json as _json, re as _re, datetime as _dt
from flask import jsonify as _jsonify

def _vsp_now_iso():
    try:
        return _dt.datetime.utcnow().isoformat() + "Z"
    except Exception:
        return ""

def _vsp_sanitize_rid(rid: str) -> str:
    rid = (rid or "").strip()
    if not rid:
        return ""
    # allow common run ids: VSP_CI_20251215_034956
    if _re.fullmatch(r"[A-Za-z0-9_.:-]+", rid):
        return rid
    return ""

def _vsp_guess_run_dir(rid: str) -> str:
    if not rid:
        return ""
    # 1) allow env override
    roots = []
    env = (_os.environ.get("VSP_RUN_ROOTS") or "").strip()
    if env:
        roots += [x for x in env.split(":") if x.strip()]

    # 2) common roots (fast checks)
    roots += [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]

    for r in roots:
        try:
            d = _Path(r) / rid
            if d.is_dir():
                return str(d)
        except Exception:
            pass

    # 3) shallow glob fallback (avoid deep recursive)
    base = _Path("/home/test/Data")
    for pat in [f"*/out_ci/{rid}", f"*/out/{rid}"]:
        try:
            for d in base.glob(pat):
                if d.is_dir():
                    return str(d)
        except Exception:
            pass

    return ""

def _vsp_read_json(path: _Path):
    try:
        return _json.loads(path.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return None

def _vsp_try_gate_files(run_dir: str):
    d = _Path(run_dir)
    for name in [
        "run_gate_summary.json",
        "run_gate_summary_v1.json",
        "run_gate_summary_v2.json",
        "run_gate.json",
        "run_gate_summary_v1.json",
    ]:
        p = d / name
        if p.is_file() and p.stat().st_size > 2:
            j = _vsp_read_json(p)
            if isinstance(j, dict):
                j.setdefault("source", f"FILE:{name}")
                return j
    return None

def _vsp_derive_gate_from_findings(run_dir: str, rid: str):
    fu = _Path(run_dir) / "findings_unified.json"
    if not fu.is_file() or fu.stat().st_size <= 2:
        return None

    j = _vsp_read_json(fu)
    if not isinstance(j, dict):
        return None

    items = j.get("items") or []
    if not isinstance(items, list):
        items = []

    counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0,"UNKNOWN":0}
    for it in items:
        if not isinstance(it, dict):
            continue
        sev = (it.get("severity") or it.get("sev") or "UNKNOWN")
        sev = str(sev).upper()
        if sev not in counts:
            sev = "UNKNOWN"
        counts[sev] += 1

    total = sum(counts.values())

    # very simple “commercial-friendly” overall:
    # - any CRITICAL/HIGH -> FAIL
    # - else any MEDIUM -> DEGRADED
    # - else OK
    if (counts["CRITICAL"] + counts["HIGH"]) > 0:
        status = "FAIL"
        reasons = [f"derived from findings_unified: CRITICAL+HIGH={(counts['CRITICAL']+counts['HIGH'])}"]
    elif counts["MEDIUM"] > 0:
        status = "DEGRADED"
        reasons = [f"derived from findings_unified: MEDIUM={counts['MEDIUM']}"]
    else:
        status = "OK"
        reasons = [f"derived from findings_unified: total={total}"]

    out = {
        "ok": True,
        "source": "DERIVED:findings_unified.json",
        "run_id": rid,
        "ci_run_dir": run_dir,
        "overall": {
            "status": status,
            "reasons": reasons + ["gate summary file missing (derived fallback)"],
            "degraded": ["gate_summary_missing_derived"],
            "ts": _vsp_now_iso(),
        },
        "counts": {
            "total": total,
            "by_severity": counts,
        },
    }
    return out

# Replace/define route: /api/vsp/run_gate_summary_v1/<rid>
try:
    _app_obj = app  # if app exists in module scope
except Exception:
    _app_obj = None

if _app_obj is not None:
    # try to unregister old endpoint name by reusing same route signature (Flask will pick last definition on reload)
    @_app_obj.route("/api/vsp/run_gate_summary_v1/<rid>", methods=["GET"])
    def api_vsp_run_gate_summary_v1(rid):
        rid0 = _vsp_sanitize_rid(rid)
        if not rid0:
            return _jsonify({
                "ok": False, "status": "ERROR", "error": "BAD_RID",
                "http_code": 400, "final": True, "run_id": rid, "ts": _vsp_now_iso()
            }), 200

        run_dir = _vsp_guess_run_dir(rid0)
        if not run_dir:
            return _jsonify({
                "ok": False, "status": "ERROR", "error": "RUN_DIR_NOT_FOUND",
                "http_code": 404, "final": True, "run_id": rid0, "ts": _vsp_now_iso()
            }), 200

        g = _vsp_try_gate_files(run_dir)
        if isinstance(g, dict):
            g.setdefault("ok", True)
            g.setdefault("run_id", rid0)
            g.setdefault("ci_run_dir", run_dir)
            # make sure minimal overall exists
            g.setdefault("overall", {"status":"DEGRADED","reasons":["missing overall in gate file"],"degraded":["gate_overall_missing"],"ts":_vsp_now_iso()})
            return _jsonify(g), 200

        d = _vsp_derive_gate_from_findings(run_dir, rid0)
        if isinstance(d, dict):
            return _jsonify(d), 200

        return _jsonify({
            "ok": False, "status": "ERROR",
            "error": "GATE_SUMMARY_MISSING",
            "http_code": 404, "final": True,
            "run_id": rid0, "ci_run_dir": run_dir,
            "ts": _vsp_now_iso()
        }), 200
'''
# If there's already a run_gate_summary_v1 route, replace its function block; else append.
if "/api/vsp/run_gate_summary_v1/<rid>" in t:
    # replace from decorator line to before next decorator / EOF
    pat = r'(?s)@app\.(?:route|get)\(\s*[\'"]/api/vsp/run_gate_summary_v1/<rid>[\'"][^\)]*\)\s*\n(?:@.*\n)?def\s+\w+\s*\(\s*rid\s*\)\s*:[\s\S]*?(?=\n@app\.|\nif __name__|\Z)'
    if re.search(pat, t):
        t2 = re.sub(pat, BLOCK.strip()+"\n", t, count=1)
        p.write_text(t2, encoding="utf-8")
        print("[OK] replaced existing run_gate_summary_v1 route")
    else:
        # can't safely replace -> append near end
        insert_at = t.rfind("\nif __name__")
        if insert_at == -1:
            t2 = t.rstrip() + "\n\n" + BLOCK.strip() + "\n"
        else:
            t2 = t[:insert_at] + "\n\n" + BLOCK.strip() + "\n\n" + t[insert_at:]
        p.write_text(t2, encoding="utf-8")
        print("[OK] appended run_gate_summary_v1 block (existing route pattern not matched)")
else:
    insert_at = t.rfind("\nif __name__")
    if insert_at == -1:
        t2 = t.rstrip() + "\n\n" + BLOCK.strip() + "\n"
    else:
        t2 = t[:insert_at] + "\n\n" + BLOCK.strip() + "\n\n" + t[insert_at:]
    p.write_text(t2, encoding="utf-8")
    print("[OK] appended run_gate_summary_v1 block (route not found)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"
echo "[OK] patched API run_gate_summary_v1 (P0 canonical)"
echo "[NEXT] restart UI + retest endpoint"
