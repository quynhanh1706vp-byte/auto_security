#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_env_${TS}"
echo "[BACKUP] $F.bak_runv1_env_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

TAG="# === VSP_RUN_V1_ENV_OVERRIDES_V1 ==="
if TAG in t:
    print("[OK] already patched"); raise SystemExit(0)

# 1) ensure import os exists
if not re.search(r'(?m)^import\s+os\b', t):
    t = "import os\n" + t

# 2) inject helper to build env overrides (allowed keys only)
helper = f"""
{TAG}
def _vsp_env_overrides_from_req(req_json: dict) -> dict:
    # allowlist only (commercial safe)
    allow = {{
        "GITLEAKS_TIMEOUT","GITLEAKS_KILL",
        "KICS_TIMEOUT","KICS_KILL",
        "CODEQL_TIMEOUT","CODEQL_KILL",
        "SEMGREP_TIMEOUT","SEMGREP_KILL",
    }}
    env = {{}}
    j = req_json or {{}}
    ov = j.get("env_overrides") or {{}}
    if isinstance(ov, dict):
        for k,v in ov.items():
            if k in allow and v is not None:
                env[str(k)] = str(v)
    return env
# === END VSP_RUN_V1_ENV_OVERRIDES_V1 ===
"""
if TAG not in t:
    # append near other helpers: after first occurrence of "def " block area, or simply near top after imports
    m = re.search(r'(?m)^\s*def\s+vsp_', t)
    at = m.start() if m else 0
    t = t[:at] + helper + "\n" + t[at:]

# 3) patch spawn subprocess env=...
# replace common patterns: subprocess.Popen(...), subprocess.run(...), Popen([...]) etc.
# We add: env={**os.environ, **_vsp_env_overrides_from_req(j)}
t2 = t
# look for "subprocess.Popen(" usage and insert env kw if not present
t2 = re.sub(
    r'(?s)(subprocess\.(?:Popen|run)\(\s*)([^)]*?)(\))',
    lambda m: m.group(0) if "env=" in m.group(2) else m.group(1)+m.group(2)+", env={**os.environ, **_vsp_env_overrides_from_req(j)}"+m.group(3),
    t2,
    count=1
)

p.write_text(t2, encoding="utf-8")
print("[OK] patched run spawn to pass env_overrides (first subprocess.* call found)")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
