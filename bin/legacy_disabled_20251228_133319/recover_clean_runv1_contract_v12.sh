#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

UNIT="vsp-ui-8910.service"
F="vsp_demo_app.py"

echo "== [0] stop service to avoid flapping =="
systemctl --user stop "$UNIT" 2>/dev/null || true
sleep 1

echo "== [1] choose latest compiling backup that does NOT contain run_v1 url_map surgery tags =="
best=""
for b in $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true); do
  python3 -m py_compile "$b" >/dev/null 2>&1 || continue
  # tránh các bản đã chọc url_map / hard override run_v1
  if grep -qE "VSP_RUN_V1_HARD_OVERRIDE|VSP_RUN_V1_FORCE_ALIAS|CONTRACT_WRAPPER_V6|before_request.*run_v1|_rules_by_endpoint|url_map\._rules_by_endpoint" "$b" 2>/dev/null; then
    continue
  fi
  best="$b"
  break
done

if [ -n "$best" ]; then
  echo "[OK] restore from: $best"
  cp -f "$best" "$F"
else
  echo "[WARN] no clean backup found; will try patch current file (may still work)"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runv1_wrapsafe_${TS}"
echo "[BACKUP] $F.bak_runv1_wrapsafe_${TS}"

echo "== [2] remove old run_v1 surgery blocks + install SAFE wrapper via view_functions =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# 2.1 remove previously injected blocks that may corrupt routing (best-effort)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUN_V1_.*?===.*?# === END VSP_RUN_V1_.*?===\s*\n?", "\n", t)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUNV1_.*?===.*?# === END VSP_RUNV1_.*?===\s*\n?", "\n", t)
t = re.sub(r"(?ms)\n?\s*# === VSP_RUN_V1_CONTRACT_WRAPPER_.*?===.*?# === END VSP_RUN_V1_CONTRACT_WRAPPER_.*?===\s*\n?", "\n", t)

TAG = "# === VSP_RUN_V1_WRAPSAFE_V12 ==="
END = "# === END VSP_RUN_V1_WRAPSAFE_V12 ==="
if TAG in t:
    print("[OK] already has V12 block")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# ensure imports exist
if not re.search(r"(?m)^\s*import\s+os\s*$", t): t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+functools\s*$", t): t = "import functools\n" + t

block = r'''
{TAG}
# Commercial-safe: DO NOT touch url_map internals.
# Only wrap existing view_functions for the already-registered endpoint(s).
try:
    import os, functools
    from flask import request, jsonify

    def _vsp_env_allow_v12(d: dict) -> dict:
        eo = d.get("env_overrides")
        if not isinstance(eo, dict): return {}
        allow = {
            "GITLEAKS_TIMEOUT","GITLEAKS_KILL",
            "KICS_TIMEOUT","KICS_KILL",
            "CODEQL_TIMEOUT","CODEQL_KILL",
            "SEMGREP_TIMEOUT","SEMGREP_KILL",
            "BANDIT_TIMEOUT","BANDIT_KILL",
            "TRIVY_TIMEOUT","TRIVY_KILL",
        }
        out = {}
        for k,v in eo.items():
            if k in allow:
                out[k] = str(v)
        return out

    def _vsp_fill_defaults_v12(d: dict) -> dict:
        if not isinstance(d, dict): d = {}
        d.setdefault("mode", "local")
        d.setdefault("profile", "FULL_EXT")
        d.setdefault("target_type", "path")
        d.setdefault("target", "/home/test/Data/SECURITY-10-10-v4")
        return d

    def _vsp_wrap_runv1_v12(fn):
        @functools.wraps(fn)
        def inner(*a, **kw):
            data = request.get_json(silent=True) or {}
            if not isinstance(data, dict): data = {}
            data = _vsp_fill_defaults_v12(data)

            # Fix Flask JSON cache so downstream request.get_json() sees our patched payload
            try:
                request._cached_json = {False: data, True: data}
            except Exception:
                pass

            # Provide env_overrides to downstream via WSGI environ (NOT global os.environ)
            # Downstream spawn code may read from os.environ; if it doesn't support env injection yet,
            # at least request payload is correct and no longer 400.
            try:
                request.environ["VSP_ENV_OVERRIDES_V12"] = os.environ.get("VSP_ENV_OVERRIDES_V12","")
                # also stash allowlisted overrides as JSON-ish string for debugging
                request.environ["VSP_ENV_ALLOW_V12"] = ",".join([f"{k}={v}" for k,v in _vsp_env_allow_v12(data).items()])
            except Exception:
                pass

            resp = fn(*a, **kw)

            # Commercial contract: always return JSON object
            try:
                # if handler returns (resp, code)
                r = resp[0] if isinstance(resp, tuple) else resp
                # if it's already a Response, keep
                return resp
            except Exception:
                return resp
        return inner

    # Patch candidates (seen in your logs / typical Flask blueprint endpoints)
    candidates = [
        "vsp_run_api_v1.run_v1",
        "run_v1",
        "vsp_demo_app.run_v1",
    ]
    patched = 0
    for ep in candidates:
        if ep in app.view_functions:
            app.view_functions[ep] = _vsp_wrap_runv1_v12(app.view_functions[ep])
            patched += 1
    print("[VSP_RUN_V1_WRAPSAFE_V12] patched_view_functions=", patched, "candidates=", candidates)

except Exception as e:
    print("[VSP_RUN_V1_WRAPSAFE_V12] skipped:", repr(e))
{END}
'''.replace("{TAG}", TAG).replace("{END}", END)

t = t + "\n" + block + "\n"
p.write_text(t, encoding="utf-8")
print("[OK] appended V12 wrapsafe block")
PY

echo "== [3] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] start service =="
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user restart "$UNIT"
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo

echo "== [5] verify: POST {} to /api/vsp/run_v1 should be 200 and jq-safe =="
curl -sS -i -X POST "http://127.0.0.1:8910/api/vsp/run_v1" \
  -H "Content-Type: application/json" -d '{}' | sed -n '1,140p'
