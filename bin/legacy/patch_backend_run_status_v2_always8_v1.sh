#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_always8_${TS}"
echo "[BACKUP] $F.bak_always8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_STATUS_ALWAYS8_TOOLS_V1 ==="
if TAG in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Heuristic: find function/route that returns run_status_v2 payload as dict (jsonify)
# We inject a postprocess block right before "return jsonify(...)" inside handler.
pat = re.compile(r"(def\s+api_vsp_run_status_v2[^(]*\([^)]*\):.*?)(\n\s*return\s+jsonify\(([^)]*)\)\s*)", re.S)

m = pat.search(s)
if not m:
    print("[ERR] cannot locate api_vsp_run_status_v2 handler by pattern")
    print("Hint: search 'run_status_v2' in vsp_demo_app.py and add block before return jsonify(payload)")
    raise SystemExit(2)

block = f"""
{TAG}
    # Force commercial invariant: always present 8 tool lanes in status payload (NOT_RUN if missing)
    try:
        _CANON_TOOLS = ["SEMGREP","GITLEAKS","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]
        _ZERO_COUNTS = {{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}}

        # payload variable name may differ; attempt common ones
        _payload = None
        for _nm in ["payload","rsp","out","data","ret","result"]:
            if _nm in locals() and isinstance(locals().get(_nm), dict):
                _payload = locals()[_nm]
                break
        if _payload is None:
            # fallback: try the argument passed into jsonify(...) if it is a dict var
            pass

        if isinstance(_payload, dict):
            tools = _payload.get("tools") or _payload.get("by_tool") or _payload.get("tool_status") or {{}}
            if isinstance(tools, dict):
                for t in _CANON_TOOLS:
                    if t not in tools:
                        tools[t] = {{
                            "tool": t,
                            "status": "NOT_RUN",
                            "verdict": "NOT_RUN",
                            "total": 0,
                            "counts": dict(_ZERO_COUNTS),
                            "reason": "missing_tool_output"
                        }}
                # normalize container key
                _payload["tools"] = tools

            # Optional: keep a stable ordered list for UI
            _payload["tools_order"] = _CANON_TOOLS
    except Exception as _e:
        try:
            _payload = locals().get("payload")
            if isinstance(_payload, dict):
                _payload.setdefault("warnings", []).append("always8_tools_patch_failed")
        except Exception:
            pass
"""

# inject block before return jsonify(...)
head = m.group(1)
ret = m.group(2)
s2 = s[:m.start(2)] + "\n" + block + "\n" + s[m.start(2):]

p.write_text(s2, encoding="utf-8")
print("[OK] injected always-8 block into api_vsp_run_status_v2")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile"
echo "[DONE] Patch applied. Restart 8910."
