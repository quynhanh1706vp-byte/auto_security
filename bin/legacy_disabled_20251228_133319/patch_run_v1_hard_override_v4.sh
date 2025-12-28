#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_hard_${TS}"
echo "[BACKUP] $F.bak_runv1_hard_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_HARD_OVERRIDE_V4 ==="
END = "# === END VSP_RUN_V1_HARD_OVERRIDE_V4 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Guard: ensure vsp_run_v1_alias exists
if not re.search(r"(?m)^def\s+vsp_run_v1_alias\s*\(", t):
    raise SystemExit("[ERR] vsp_run_v1_alias() not found; cannot hard-override /api/vsp/run_v1")

block = f"""

{TAG}
# Commercial: remove ANY existing POST rule for /api/vsp/run_v1, then bind it to vsp_run_v1_alias()
try:
    _um = app.url_map
    _removed = 0

    # remove matching rules from internal structures (Werkzeug Map)
    for _r in list(getattr(_um, "_rules", [])):
        try:
            if getattr(_r, "rule", None) == "/api/vsp/run_v1" and ("POST" in (getattr(_r, "methods", None) or set())):
                # remove from _rules
                _um._rules.remove(_r)
                # remove from _rules_by_endpoint
                _ep = getattr(_r, "endpoint", None)
                if _ep in getattr(_um, "_rules_by_endpoint", {}):
                    _lst = _um._rules_by_endpoint.get(_ep) or []
                    if _r in _lst:
                        _lst.remove(_r)
                    if not _lst:
                        try: del _um._rules_by_endpoint[_ep]
                        except Exception: pass
                _removed += 1
        except Exception:
            pass

    try:
        _um._remap = True
    except Exception:
        pass

    # Now add fresh rule bound to alias (unique endpoint)
    app.add_url_rule(
        "/api/vsp/run_v1",
        endpoint="__vsp_run_v1_force_v4",
        view_func=vsp_run_v1_alias,
        methods=["POST"],
    )
    print("[VSP_RUN_V1_HARD_OVERRIDE_V4] removed_rules=", _removed, "-> rebound /api/vsp/run_v1 to vsp_run_v1_alias()")
except Exception as _e:
    print("[VSP_RUN_V1_HARD_OVERRIDE_V4][WARN]", repr(_e))
{END}
"""

t = t.rstrip() + "\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended hard override block")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1

echo "== verify POST {} to /api/vsp/run_v1 (should be 200, not 400) =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" \
  -d '{}' | sed -n '1,140p'
