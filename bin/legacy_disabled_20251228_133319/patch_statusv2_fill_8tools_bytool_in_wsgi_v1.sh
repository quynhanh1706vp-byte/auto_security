#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fill8_${TS}"
echo "[BACKUP] $F.bak_fill8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_FILL8_BYTOOL_V1"
if TAG in t:
    print("[OK] fill8 already installed, skip")
    raise SystemExit(0)

BLOCK = r'''

# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_FILL8_BYTOOL_V1 ===
def _vsp_statusv2_fill8_bytool(obj: dict) -> dict:
    """
    Ensure run_gate_summary.by_tool includes 8 commercial tools keys.
    If missing, set verdict=NOT_RUN and total=0 (do NOT override existing).
    """
    want = ["SEMGREP","TRIVY","KICS","GITLEAKS","CODEQL","BANDIT","SYFT","GRYPE"]
    try:
        rgs = obj.get("run_gate_summary") or {}
        by_tool = rgs.get("by_tool") or {}
        if not isinstance(by_tool, dict):
            by_tool = {}
        changed = False
        for k in want:
            if k not in by_tool:
                by_tool[k] = {"tool": k, "verdict": "NOT_RUN", "total": 0}
                changed = True
            else:
                # normalize shape a bit (keep existing verdict/total)
                v = by_tool.get(k) or {}
                if isinstance(v, dict):
                    if "tool" not in v:
                        v["tool"] = k
                        changed = True
                    by_tool[k] = v
        if changed:
            rgs["by_tool"] = by_tool
            obj["run_gate_summary"] = rgs
    except Exception:
        pass
    return obj

def _vsp_try_fill8_on_json_bytes(b: bytes) -> bytes:
    import json
    try:
        obj = json.loads(b.decode("utf-8", errors="ignore"))
        if isinstance(obj, dict) and obj.get("ok") is True:
            obj2 = _vsp_statusv2_fill8_bytool(obj)
            return json.dumps(obj2, ensure_ascii=False).encode("utf-8")
    except Exception:
        return b
    return b

# Hook into existing bytes postprocess chain if present; otherwise wrap WSGI app at the end.
try:
    # If there is a global postprocess dispatcher, extend it
    if "_VSP_STATUSV2_BYTES_POSTPROCESSORS" in globals() and isinstance(globals().get("_VSP_STATUSV2_BYTES_POSTPROCESSORS"), list):
        globals()["_VSP_STATUSV2_BYTES_POSTPROCESSORS"].append(_vsp_try_fill8_on_json_bytes)
    else:
        globals()["_VSP_STATUSV2_BYTES_POSTPROCESSORS"] = [_vsp_try_fill8_on_json_bytes]
except Exception:
    pass
# === /VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_FILL8_BYTOOL_V1 ===
'''

# Append near end (safe)
p.write_text(t + "\n" + BLOCK + "\n", encoding="utf-8")
print("[OK] appended fill8-by_tool postprocess block")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py
echo "[OK] py_compile wsgi_vsp_ui_gateway.py"

echo "[DONE] Patch installed. Now restart 8910 (no sudo)."
