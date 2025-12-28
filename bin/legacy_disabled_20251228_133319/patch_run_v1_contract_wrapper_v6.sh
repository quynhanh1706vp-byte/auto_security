#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_wrap_v6_${TS}"
echo "[BACKUP] $F.bak_runv1_wrap_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_CONTRACT_WRAPPER_V6 ==="
END = "# === END VSP_RUN_V1_CONTRACT_WRAPPER_V6 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# Ensure os import exists (for env overrides safety)
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    t = "import os\n" + t

block = r'''
# Commercial: stable /api/vsp/run_v1 that accepts {} and delegates to vsp_run_api_v1.run_v1 with a safe request context.
try:
    from flask import request, jsonify
except Exception:
    request = None
    jsonify = None

def __vsp_run_v1_contract_wrapper_v6():
    # 1) parse json safely
    try:
        j = (request.get_json(silent=True) or {}) if request else {}
        if not isinstance(j, dict):
            j = {}
    except Exception:
        j = {}

    # 2) minimal defaults (commercial)
    j.setdefault("mode", "local")
    j.setdefault("profile", "FULL_EXT")
    j.setdefault("target_type", "path")
    j.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")

    # keep env_overrides if present (must be dict)
    if not isinstance(j.get("env_overrides"), dict):
        j.pop("env_overrides", None)

    # 3) delegate to the real run_v1 implementation (already working when full payload is provided)
    try:
        import vsp_run_api_v1  # the module you already registered
        fn = getattr(vsp_run_api_v1, "run_v1", None)
    except Exception:
        fn = None

    # Use a local request context so downstream sees JSON correctly (no _cached_json hacks)
    try:
        with app.test_request_context("/api/vsp/run_v1", method="POST", json=j):
            if callable(fn):
                return fn()
            # fallback to alias if module missing
            try:
                return vsp_run_v1_alias()
            except Exception:
                pass
    except Exception as e:
        pass

    # final fallback
    try:
        return jsonify({"ok": False, "error": "RUN_V1_WRAPPER_FAILED", "hint": "check vsp_run_api_v1.run_v1 import"}) , 500
    except Exception:
        return ("{\"ok\":false,\"error\":\"RUN_V1_WRAPPER_FAILED\"}", 500, {"Content-Type":"application/json"})

# Hard override: remove all POST rules for /api/vsp/run_v1 then bind to wrapper
try:
    _um = app.url_map
    _targets = []
    for _r in list(getattr(_um, "_rules", [])):
        try:
            if getattr(_r, "rule", None) == "/api/vsp/run_v1" and ("POST" in (getattr(_r, "methods", None) or set())):
                _targets.append(_r)
        except Exception:
            pass

    for _r in _targets:
        try:
            if _r in _um._rules:
                _um._rules.remove(_r)
        except Exception:
            pass
        try:
            _ep = getattr(_r, "endpoint", None)
            _rbe = getattr(_um, "_rules_by_endpoint", None)
            if isinstance(_rbe, dict) and _ep in _rbe:
                _lst = _rbe.get(_ep) or []
                if _r in _lst:
                    _lst.remove(_r)
                if not _lst:
                    try:
                        del _rbe[_ep]
                    except Exception:
                        pass
        except Exception:
            pass

    try:
        _um._remap = True
    except Exception:
        pass

    app.add_url_rule(
        "/api/vsp/run_v1",
        endpoint="__vsp_run_v1_contract_wrapper_v6",
        view_func=__vsp_run_v1_contract_wrapper_v6,
        methods=["POST"],
    )
    print("[VSP_RUN_V1_CONTRACT_WRAPPER_V6] rebound /api/vsp/run_v1 -> wrapper_v6 (accept {})")
except Exception as _e:
    print("[VSP_RUN_V1_CONTRACT_WRAPPER_V6][WARN]", repr(_e))
'''

t = t.rstrip() + "\n\n" + TAG + "\n" + block.strip("\n") + "\n" + END + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended wrapper_v6 + hard override")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (MUST be 200 now) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,160p'
