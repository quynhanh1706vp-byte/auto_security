#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

grep -q "VSP_RULE_OVERRIDES_API_V1" "$F" && { echo "[OK] api block already present"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_rule_overrides_${TS}"
echo "[BACKUP] $F.bak_rule_overrides_${TS}"

cat >> "$F" <<'PY'

# === VSP_RULE_OVERRIDES_API_V1 BEGIN ===
import json
from pathlib import Path
from flask import request, jsonify

_RULE_OVR_PATH = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/vsp_rule_overrides_v1.json")

def _rule_ovr_default():
    return {
        "meta": {"version": "v1", "updated_at": None},
        "overrides": []
    }

@app.route("/api/vsp/rule_overrides_v1", methods=["GET"])
def api_vsp_rule_overrides_get_v1():
    if _RULE_OVR_PATH.exists():
        try:
            return jsonify(json.load(open(_RULE_OVR_PATH, "r", encoding="utf-8")))
        except Exception:
            return jsonify(_rule_ovr_default()), 200
    return jsonify(_rule_ovr_default()), 200

@app.route("/api/vsp/rule_overrides_v1", methods=["POST"])
def api_vsp_rule_overrides_post_v1():
    data = request.get_json(silent=True) or _rule_ovr_default()
    try:
        data.setdefault("meta", {})
        data["meta"]["updated_at"] = __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat()
        _RULE_OVR_PATH.parent.mkdir(parents=True, exist_ok=True)
        json.dump(data, open(_RULE_OVR_PATH, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
        return jsonify({"ok": True, "file": str(_RULE_OVR_PATH)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
# === VSP_RULE_OVERRIDES_API_V1 END ===
PY

python3 -m py_compile "$F"
echo "[OK] patched + py_compile OK => $F"
