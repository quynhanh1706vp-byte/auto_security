#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rule_apply_intercept_${TS}"
echo "[BACKUP] ${W}.bak_rule_apply_intercept_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RULE_OVERRIDES_APPLY_INTERCEPT_V3"
if marker in s:
    print("[OK] marker already present, skip.")
    raise SystemExit(0)

# detect Flask app variable (default app)
m = re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
appvar = m.group(1) if m else "app"

# ensure impl exists (you already added in V2, but keep safe)
if "_vsp_rule_overrides_apply_impl" not in s:
    addon_impl = f"""
# VSP_P1_RULE_OVERRIDES_APPLY_EP_V2_MIN (autoinsert)
def _vsp_rule_overrides_apply_impl():
    from flask import request, jsonify
    import json, time
    from pathlib import Path
    ts = int(time.time())
    payload = request.get_json(silent=True) or {{}}
    rid = (request.args.get("rid") or payload.get("rid") or payload.get("RUN_ID") or payload.get("run_id") or "").strip()
    if not rid:
        return jsonify(ok=False, error="RID_MISSING", ts=ts), 400
    rp = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json")
    if not rp.exists():
        rp = Path(__file__).resolve().parent / "out_ci" / "rule_overrides_v2" / "rules.json"
    if not rp.exists():
        return jsonify(ok=False, error="RULES_NOT_FOUND", ts=ts, rid=rid, rules_path=str(rp)), 404
    txt = rp.read_text(encoding="utf-8", errors="replace") or "{{}}"
    try:
        _ = json.loads(txt)
    except Exception as e:
        return jsonify(ok=False, error="RULES_JSON_INVALID", detail=str(e), ts=ts, rid=rid, rules_path=str(rp)), 400
    out_dir = rp.parent
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "last_apply.json").write_text(
        json.dumps({{"ok": True, "rid": rid, "rules_path": str(rp), "ts": ts}}, indent=2),
        encoding="utf-8"
    )
    return jsonify(ok=True, rid=rid, rules_path=str(rp), ts=ts)
"""
    s += "\n" + addon_impl + "\n"

addon = f"""
# {marker}
@{appvar}.before_request
def _vsp_p1_rule_overrides_apply_intercept_v3():
    \"\"\"Intercept Apply POST even if route missing or 404 handler would wrap it.\"\"\"
    try:
        from flask import request
        if request.method == "POST" and request.path in (
            "/api/ui/rule_overrides_v2_apply_v2",
            "/api/ui/rule_overrides_v2_apply",
        ):
            return _vsp_rule_overrides_apply_impl()
    except Exception:
        return None
    return None
"""

# append at end (safe)
if not s.endswith("\n"):
    s += "\n"
s += "\n" + addon + "\n"

w.write_text(s, encoding="utf-8")
print("[OK] appended intercept using appvar=", appvar)
PY

python3 -m py_compile "$W" && echo "[OK] py_compile OK"
echo "[NEXT] restart UI and re-test POST apply endpoint."
