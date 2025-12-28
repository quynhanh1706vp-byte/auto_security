#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p553_${TS}"
echo "[OK] backup => ${APP}.bak_p553_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# remove old run_status_v1 handlers (if any)
routes = ["run_status_v1"]
pat = re.compile(r"(?ms)^@app\.route\([^\n]*?/api/vsp/(?:%s)[^\n]*\)\n.*?(?=^@app\.route|\Z)" % "|".join(routes))
s2 = pat.sub("", s)

new_block = r'''
# =========================
# P553: run_status_v1 contract (RUNNING/FINISHED/DEGRADED/FAILED)
# - based on artifacts presence (no dependency on runner internals)
# =========================
from flask import request, jsonify

def _p553_state_from_artifacts(run_dir: Path):
    # markers / signals
    fail_markers = [
        "FAILED.marker", "fail.marker", "FAILED", "error.marker"
    ]
    for nm in fail_markers:
        try:
            for h in run_dir.glob(f"**/{nm}"):
                if h.is_file():
                    return "FAILED", f"marker:{nm}"
        except Exception:
            pass

    # read run_gate_summary if present (prefer)
    summary = None
    summ_path = _p552_find_first(run_dir, ["run_gate_summary.json", "run_gate.json"]) if "_p552_find_first" in globals() else None
    if summ_path and summ_path.is_file():
        try:
            summary = json.loads(summ_path.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            summary = None

    # completion evidence: findings + summary
    findings_path = _p552_find_first(run_dir, ["findings_unified.json","findings_unified.csv","findings_unified.sarif","findings.json"]) if "_p552_find_first" in globals() else None
    done = bool(summ_path and summ_path.is_file() and findings_path and findings_path.is_file())

    # determine degraded from summary fields or known flags
    degraded = False
    if isinstance(summary, dict):
        # typical fields we might see
        if summary.get("degraded") is True:
            degraded = True
        if str(summary.get("state","")).upper() == "DEGRADED":
            degraded = True
        if str(summary.get("status","")).upper() == "DEGRADED":
            degraded = True
        # tool timeouts / missing tools often appear in text fields
        blob = json.dumps(summary, ensure_ascii=False).lower()
        if "timeout" in blob or "missing tool" in blob or "degrad" in blob:
            # only mark degraded when done, otherwise still running
            if done:
                degraded = True

        # hard fail hints
        if str(summary.get("state","")).upper() in ("FAILED","ERROR"):
            return "FAILED", "summary_state"

        if str(summary.get("verdict","")).lower() in ("fail","failed","error"):
            return "FAILED", "summary_verdict"

    if done:
        return ("DEGRADED" if degraded else "FINISHED"), "done_artifacts"

    # if we have some run progress traces => RUNNING
    progress = ["run_manifest.json", "run_status.json", "steps_log.jsonl", "tool_status.json"]
    for nm in progress:
        try:
            for h in run_dir.glob(f"**/{nm}"):
                if h.is_file():
                    return "RUNNING", f"progress:{nm}"
        except Exception:
            pass

    # default: RUNNING if directory exists but not done yet
    return "RUNNING", "dir_exists"

@app.route("/api/vsp/run_status_v1/<rid>")
def api_vsp_run_status_v1_path(rid):
    rid = (rid or "").strip()
    run_dir = _p552_resolve_run_dir(rid) if "_p552_resolve_run_dir" in globals() else None
    if not run_dir:
        return jsonify({"ok": False, "err": "rid_not_found", "rid": rid}), 404
    state, reason = _p553_state_from_artifacts(run_dir)
    return jsonify({
        "ok": True,
        "rid": rid,
        "state": state,
        "reason": reason,
        "ts": int(time.time()),
        "run_dir": str(run_dir),
    })

@app.route("/api/vsp/run_status_v1")
def api_vsp_run_status_v1_qs():
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing_rid"}), 400
    run_dir = _p552_resolve_run_dir(rid) if "_p552_resolve_run_dir" in globals() else None
    if not run_dir:
        return jsonify({"ok": False, "err": "rid_not_found", "rid": rid}), 404
    state, reason = _p553_state_from_artifacts(run_dir)
    return jsonify({
        "ok": True,
        "rid": rid,
        "state": state,
        "reason": reason,
        "ts": int(time.time()),
        "run_dir": str(run_dir),
    })
'''

m = re.search(r"(?m)^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s2)
if m:
    out = s2[:m.start()] + new_block + "\n\n" + s2[m.start():]
else:
    out = s2 + "\n\n" + new_block + "\n"

p.write_text(out, encoding="utf-8")
print("[OK] patched run_status_v1 routes")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"

if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
# wait port
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null; then
    echo "[OK] UI up"
    break
  fi
  sleep 1
done

RID="${RID:-VSP_CI_20251219_092640}"
echo "== probe run_status_v1 path =="
curl -sS "$BASE/api/vsp/run_status_v1/$RID" | python3 -m json.tool
echo "== probe run_status_v1 qs =="
curl -sS "$BASE/api/vsp/run_status_v1?rid=$RID" | python3 -m json.tool
