#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_hard_v5_${TS}"
echo "[BACKUP] $F.bak_runv1_hard_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_HARD_OVERRIDE_V5 ==="
END = "# === END VSP_RUN_V1_HARD_OVERRIDE_V5 ==="

if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Guard: ensure vsp_run_v1_alias exists
if not re.search(r"(?m)^def\s+vsp_run_v1_alias\s*\(", t):
    raise SystemExit("[ERR] vsp_run_v1_alias() not found; cannot hard-override /api/vsp/run_v1")

code = r'''
# Commercial: remove ANY existing POST rule for /api/vsp/run_v1, then bind it to vsp_run_v1_alias()
try:
    _um = app.url_map
    _removed = 0

    # Collect targets first
    _targets = []
    for _r in list(getattr(_um, "_rules", [])):
        try:
            if getattr(_r, "rule", None) == "/api/vsp/run_v1" and ("POST" in (getattr(_r, "methods", None) or set())):
                _targets.append(_r)
        except Exception:
            pass

    # Remove from internal lists
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
        _removed += 1

    # Force remap (Werkzeug Map)
    try:
        _um._remap = True
    except Exception:
        pass

    # Add a fresh rule bound to alias (unique endpoint)
    try:
        app.add_url_rule(
            "/api/vsp/run_v1",
            endpoint="__vsp_run_v1_force_v5",
            view_func=vsp_run_v1_alias,
            methods=["POST"],
        )
    except Exception as _e2:
        print("[VSP_RUN_V1_HARD_OVERRIDE_V5][WARN] add_url_rule failed:", repr(_e2))

    print("[VSP_RUN_V1_HARD_OVERRIDE_V5] removed_rules=", _removed, "-> rebound /api/vsp/run_v1 to vsp_run_v1_alias()")
except Exception as _e:
    print("[VSP_RUN_V1_HARD_OVERRIDE_V5][WARN]", repr(_e))
'''

block = "\n\n" + TAG + "\n" + code.strip("\n") + "\n" + END + "\n"
t = t.rstrip() + block
p.write_text(t, encoding="utf-8")
print("[OK] appended hard override V5 block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (should be 200, not 400) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,140p'
