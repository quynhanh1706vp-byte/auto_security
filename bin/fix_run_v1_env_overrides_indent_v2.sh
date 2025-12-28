#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_envfix_v2_${TS}"
echo "[BACKUP] $F.bak_envfix_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUN_V1_ENV_OVERRIDES_V1 ==="
END = "# === END VSP_RUN_V1_ENV_OVERRIDES_V1 ==="

# 1) Remove broken helper block if exists (wherever it was inserted)
blk = re.compile(r"(?ms)\n?\s*# === VSP_RUN_V1_ENV_OVERRIDES_V1 ===.*?# === END VSP_RUN_V1_ENV_OVERRIDES_V1 ===\s*\n?")
t, n_rm = blk.subn("\n", t)

# 2) Ensure import os exists (top-level)
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    # Insert after first import group; fallback: top
    m = re.search(r"(?m)^(import .+\n)+", t)
    if m:
        t = t[:m.end()] + "import os\n" + t[m.end():]
    else:
        t = "import os\n" + t

# 3) Insert helper at top-level near other helpers (before first def vsp_*)
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
        for k, v in ov.items():
            if k in allow and v is not None:
                env[str(k)] = str(v)
    return env
{END}
"""

if TAG not in t:
    m = re.search(r"(?m)^def\s+vsp_", t)
    at = m.start() if m else 0
    t = t[:at] + helper + "\n" + t[at:]

# 4) Patch ONLY vsp_run_v1_alias(): add env merge + pass env= to subprocess.Popen/run
m0 = re.search(r"(?m)^def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*$", t)
if not m0:
    raise SystemExit("[ERR] cannot find def vsp_run_v1_alias()")

m1 = re.search(r"(?m)^def\s+\w+\s*\(", t[m0.end():])
end = (m0.end() + m1.start()) if m1 else len(t)
seg = t[m0.start():end]

# Find 'j =' (parsed json) within function; fallback: create one from request.get_json
if "_vsp_env_overrides_from_req" not in seg:
    # Ensure we have 'j' dict
    if not re.search(r"(?m)^\s*j\s*=\s*", seg):
        # insert after first line of function body
        lines = seg.splitlines(True)
        if len(lines) >= 2:
            # insert after def line
            ins = "    j = (request.get_json(silent=True) or {})\n"
            seg = lines[0] + ins + "".join(lines[1:])

    # Insert env merge right after j is defined
    seg = re.sub(
        r"(?m)^(\s*j\s*=\s*[^\n]*\n)",
        r"\1    env = dict(os.environ)\n    env.update(_vsp_env_overrides_from_req(j))\n",
        seg,
        count=1
    )

# Now ensure subprocess calls use env=env
# Only patch first subprocess.Popen/run inside this function segment if not already env=
if "subprocess.Popen" in seg and "env=" not in seg:
    seg = re.sub(r"(?s)(subprocess\.Popen\s*\()",
                 r"\1",
                 seg, count=1)
    # inject env=env as a kwarg on the same call (best-effort): add after first '(' line
    seg = re.sub(r"(?m)^(\s*proc\s*=\s*subprocess\.Popen\s*\([^\n]*\n)",
                 r"\1        env=env,\n",
                 seg, count=1)
    # if pattern above didn't match, try a looser insert right after the first line containing subprocess.Popen(
    if "env=env" not in seg:
        seg = re.sub(r"(?m)^(\s*.*subprocess\.Popen\s*\([^\n]*\n)",
                     r"\1        env=env,\n",
                     seg, count=1)

if "subprocess.run" in seg and "env=" not in seg:
    seg = re.sub(r"(?m)^(\s*.*subprocess\.run\s*\([^\n]*\n)",
                 r"\1        env=env,\n",
                 seg, count=1)

t = t[:m0.start()] + seg + t[end:]

p.write_text(t, encoding="utf-8")
print("[OK] env_overrides helper reinserted top-level; vsp_run_v1_alias patched")
print("[OK] removed old blocks:", n_rm)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

systemctl --user restart vsp-ui-8910.service
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
curl -sS http://127.0.0.1:8910/api/vsp/version | jq
