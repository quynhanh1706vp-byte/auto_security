#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

UNIT="$HOME/.config/systemd/user/vsp-ui-8910.service"

echo "== [0] stop service to avoid flapping =="
systemctl --user stop vsp-ui-8910.service 2>/dev/null || true

echo "== [1] find latest backup that compiles =="
best=""
for f in $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true); do
  cp -f "$f" /tmp/vsp_demo_app_try.py
  if python3 -m py_compile /tmp/vsp_demo_app_try.py >/dev/null 2>&1; then
    best="$f"
    break
  fi
done

if [ -z "$best" ]; then
  echo "[WARN] no compiling backup found; will try to fix current file anyway"
else
  echo "[OK] restore from: $best"
  cp -f "$best" vsp_demo_app.py
fi

echo "== [2] apply ultra-safe env_overrides patch (no indentation injection lines) =="

TS="$(date +%Y%m%d_%H%M%S)"
cp -f vsp_demo_app.py "vsp_demo_app.py.bak_envov3_${TS}"
echo "[BACKUP] vsp_demo_app.py.bak_envov3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove any previous broken blocks (anywhere)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUN_V1_ENV_OVERRIDES_V1 ===.*?# === END VSP_RUN_V1_ENV_OVERRIDES_V1 ===\s*\n?", "\n", t)

# ensure import os exists
if not re.search(r"(?m)^\s*import\s+os\s*$", t):
    m = re.search(r"(?m)^(import .+\n)+", t)
    if m:
        t = t[:m.end()] + "import os\n" + t[m.end():]
    else:
        t = "import os\n" + t

TAG = "# === VSP_RUN_V1_ENV_OVERRIDES_V3 ==="
END = "# === END VSP_RUN_V1_ENV_OVERRIDES_V3 ==="

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
    # append helper at EOF to guarantee top-level indent
    t = t.rstrip() + "\n\n" + helper + "\n"

# --- patch ONLY vsp_run_v1_alias() segment ---
m0 = re.search(r"(?m)^def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*$", t)
if not m0:
    raise SystemExit("[ERR] cannot find def vsp_run_v1_alias()")

m1 = re.search(r"(?m)^def\s+\w+\s*\(", t[m0.end():])
end = (m0.end() + m1.start()) if m1 else len(t)
seg = t[m0.start():end]

# make sure we have j = request.get_json...
if not re.search(r"(?m)^\s*j\s*=\s*", seg):
    seg = re.sub(r"(?m)^(def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*\n)",
                 r"\1    j = (request.get_json(silent=True) or {})\n",
                 seg, count=1)

# ensure env building right after j= line (same indent)
if "_vsp_env_overrides_from_req" not in seg or "env.update(" not in seg:
    seg = re.sub(r"(?m)^(\s*j\s*=\s*[^\n]*\n)",
                 r"\1    env = dict(os.environ)\n    env.update(_vsp_env_overrides_from_req(j))\n",
                 seg, count=1)

def inject_env_kw(call_name: str, text: str) -> str:
    # inject ", env=env" just before the matching ")" of the first call that lacks env=
    idx = text.find(call_name + "(")
    if idx < 0:
        return text
    # quick skip if already has env= in that call slice (best-effort)
    slice_ = text[idx: idx+6000]
    if "env=" in slice_.split(")",1)[0]:
        return text

    i = idx + len(call_name) + 1
    depth = 1
    in_s = None
    esc = False
    while i < len(text) and depth > 0:
        ch = text[i]
        if in_s:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_s:
                in_s = None
        else:
            if ch in ("'", '"'):
                in_s = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    # inject before this ')'
                    return text[:i] + ", env=env" + text[i:]
        i += 1
    return text

# Inject into subprocess.Popen and subprocess.run inside this function segment
seg2 = seg
seg2 = inject_env_kw("subprocess.Popen", seg2)
seg2 = inject_env_kw("subprocess.run", seg2)

t = t[:m0.start()] + seg2 + t[end:]

p.write_text(t, encoding="utf-8")
print("[OK] patched vsp_run_v1_alias with env=env injection; helper appended at EOF")
PY

echo "== [3] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] restart service =="
systemctl --user start vsp-ui-8910.service
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
curl -sS http://127.0.0.1:8910/api/vsp/version | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("ok"), json.loads(sys.stdin.read()).get("info",{}).get("service"))'
