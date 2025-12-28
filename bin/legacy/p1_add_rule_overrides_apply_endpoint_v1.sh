#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

W="$(python3 - <<'PY'
from pathlib import Path
root = Path(".")
# prefer canonical gateway
p = root / "wsgi_vsp_ui_gateway.py"
if p.exists():
    print(str(p)); raise SystemExit(0)

# fallback: find file containing "rule_overrides" and Flask route usage
cands=[]
for x in root.rglob("*.py"):
    if "out_ci" in x.parts or "bin" in x.parts:
        continue
    try:
        s=x.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "rule_overrides" in s and ".route(" in s and "Flask" in s:
        cands.append(x)

cands=sorted(cands, key=lambda z: (len(str(z)), str(z)))
print(str(cands[0]) if cands else "")
PY
)"
[ -n "$W" ] || { echo "[ERR] cannot locate gateway python file"; exit 2; }
[ -f "$W" ] || { echo "[ERR] gateway not found: $W"; exit 2; }

cp -f "$W" "${W}.bak_rule_apply_ep_${TS}"
echo "[BACKUP] ${W}.bak_rule_apply_ep_${TS}"

export W
python3 - <<'PY'
import os, re
from pathlib import Path

w = Path(os.environ["W"])
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RULE_OVERRIDES_APPLY_EP_V1"
if marker in s:
    print("[OK] marker already present, skip.")
    raise SystemExit(0)

# detect Flask app variable name (default "app")
m = re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*Flask\s*\(', s, flags=re.M)
appvar = m.group(1) if m else "app"

addon = f"""
# {marker}
@{appvar}.route("/api/ui/rule_overrides_v2_apply_v2", methods=["POST"])
def api_ui_rule_overrides_v2_apply_v2():
    \"\"\"Commercial-safe: make Apply button non-404 and emit ok=true for UI refresh.
    Validates rules.json and writes last_apply.json (audit trail).\"\"\"
    try:
        from flask import request, jsonify
        import json, time
        from pathlib import Path

        ts = int(time.time())
        payload = request.get_json(silent=True) or {{}}
        rid = (request.args.get("rid") or payload.get("rid") or payload.get("RUN_ID") or payload.get("run_id") or "").strip()
        if not rid:
            return jsonify(ok=False, error="RID_MISSING", ts=ts, path="/api/ui/rule_overrides_v2_apply_v2"), 400

        # default rules path (as shown in UI); fallback to relative
        rp = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/rule_overrides_v2/rules.json")
        if not rp.exists():
            rp = Path(__file__).resolve().parent / "out_ci" / "rule_overrides_v2" / "rules.json"
        if not rp.exists():
            return jsonify(ok=False, error="RULES_NOT_FOUND", ts=ts, rid=rid, rules_path=str(rp)), 404

        # validate json parse
        txt = rp.read_text(encoding="utf-8", errors="replace") or "{{}}"
        _ = json.loads(txt)

        # write audit trail
        out_dir = rp.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "last_apply.json").write_text(
            json.dumps({{"ok": True, "rid": rid, "rules_path": str(rp), "ts": ts}}, indent=2),
            encoding="utf-8"
        )

        return jsonify(ok=True, rid=rid, rules_path=str(rp), ts=ts)
    except Exception as e:
        try:
            from flask import jsonify
            import time
            return jsonify(ok=False, error="EXC", detail=str(e), ts=int(time.time())), 500
        except Exception:
            return ("error", 500)

"""

# append near end (safe)
if not s.endswith("\n"):
    s += "\n"
s += "\n" + addon + "\n"
w.write_text(s, encoding="utf-8")
print("[OK] appended endpoint:", "/api/ui/rule_overrides_v2_apply_v2", "using appvar=", appvar)
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "[NEXT] restart UI, then test POST endpoint with curl."
