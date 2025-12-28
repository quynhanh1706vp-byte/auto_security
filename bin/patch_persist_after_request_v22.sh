#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_afterreq_v22_${TS}"
echo "[BACKUP] $F.bak_persist_afterreq_v22_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PERSIST_AFTER_REQUEST_V22" in txt:
    print("[OK] already patched V22.")
    raise SystemExit(0)

# Ensure we have a small helper set (independent of previous V19/V20)
HELP = r'''
# === VSP_PERSIST_AFTER_REQUEST_V22 ===
import os as _os
import json as _json
import time as _time
import traceback as _traceback
from flask import request as _vsp_req

_VSP_UIREQ_DIR_V22 = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1"
_VSP_HIT_LOG_V22   = _VSP_UIREQ_DIR_V22 + "/_persist_hits.log"
_VSP_ERR_LOG_V22   = _VSP_UIREQ_DIR_V22 + "/_persist_err.log"

def _vsp_append_v22(path, line):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V22, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:
        pass

def _vsp_merge_write_v22(rid: str, payload: dict):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V22, exist_ok=True)
        fp = _os.path.join(_VSP_UIREQ_DIR_V22, f"{rid}.json")
        try:
            cur = _json.loads(open(fp, "r", encoding="utf-8").read())
        except Exception:
            cur = {"ok": True, "req_id": rid}

        if not isinstance(payload, dict):
            payload = {}

        # commercial: don't overwrite good values with None/""
        for k, v in payload.items():
            if v is None:
                continue
            if k in ("ci_run_dir","runner_log","stage_sig") and v == "":
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or rid
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = fp + ".tmp"
        open(tmp, "w", encoding="utf-8").write(_json.dumps(cur, ensure_ascii=False, indent=2))
        _os.replace(tmp, fp)
        return True
    except Exception as e:
        _vsp_append_v22(_VSP_ERR_LOG_V22, f"merge_write_fail rid={rid} err={repr(e)} file={__file__}")
        _vsp_append_v22(_VSP_ERR_LOG_V22, _traceback.format_exc())
        return False

def _vsp_try_json_v22(resp):
    try:
        if hasattr(resp, "get_json"):
            j = resp.get_json(silent=True)
            if isinstance(j, dict):
                return j
        if hasattr(resp, "get_data"):
            s = resp.get_data(as_text=True)
            if isinstance(s, str):
                s2 = s.strip()
                if s2.startswith("{") and s2.endswith("}"):
                    j = _json.loads(s2)
                    if isinstance(j, dict):
                        return j
    except Exception:
        return None
    return None
# === END VSP_PERSIST_AFTER_REQUEST_V22 ===
'''.lstrip("\n")

# Insert helper after import block (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + HELP + "\n" + txt[m.end():]
else:
    ls = txt.splitlines(True)
    txt = "".join(ls[:1]) + "\n" + HELP + "\n" + "".join(ls[1:])

# Insert after_request hook near where app is created (after "app = Flask(")
hook = r'''
# === VSP_AFTER_REQUEST_PERSIST_HOOK_V22 ===
@app.after_request
def vsp_after_request_persist_uireq_v22(resp):
    try:
        path = _vsp_req.path or ""
        # 1) persist from run_v1 response (RID comes from response json)
        if path.startswith("/api/vsp/run_v1"):
            payload = _vsp_try_json_v22(resp)
            if isinstance(payload, dict):
                rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
                if rid:
                    _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22 run_v1 ts={_time.time()} rid={rid}")
                    _vsp_merge_write_v22(str(rid), payload)

        # 2) persist from run_status_v1 response (RID comes from URL path param)
        if path.startswith("/api/vsp/run_status_v1/"):
            rid = path.rsplit("/", 1)[-1]
            payload = _vsp_try_json_v22(resp)
            if not isinstance(payload, dict):
                payload = {"ok": True, "req_id": rid}
            payload["req_id"] = payload.get("req_id") or rid
            _vsp_append_v22(_VSP_HIT_LOG_V22, f"after_v22 status ts={_time.time()} rid={rid}")
            _vsp_merge_write_v22(str(rid), payload)
    except Exception as e:
        _vsp_append_v22(_VSP_ERR_LOG_V22, f"after_v22_fail err={repr(e)} file={__file__}")
        _vsp_append_v22(_VSP_ERR_LOG_V22, _traceback.format_exc())
    return resp
# === END VSP_AFTER_REQUEST_PERSIST_HOOK_V22 ===
'''.lstrip("\n")

if "VSP_AFTER_REQUEST_PERSIST_HOOK_V22" not in txt:
    m2 = re.search(r'^\s*app\s*=\s*Flask\s*\(', txt, flags=re.M)
    if not m2:
        # fallback: append near top
        txt = txt + "\n\n" + hook + "\n"
    else:
        # insert after the line containing app = Flask(...)
        lines = txt.splitlines(True)
        # find the line index
        idx = 0
        pos = m2.start()
        cur = 0
        for i, ln in enumerate(lines):
            if cur <= pos < cur + len(ln):
                idx = i
                break
            cur += len(ln)
        # insert after idx+1
        lines.insert(idx+1, "\n" + hook + "\n")
        txt = "".join(lines)

p.write_text(txt, encoding="utf-8")
print("[OK] inserted V22 after_request persist hook into vsp_demo_app.py")
PY

python3 -m py_compile "$F" >/dev/null && echo "[OK] py_compile passed"
grep -n "VSP_AFTER_REQUEST_PERSIST_HOOK_V22" -n "$F" | head -n 5 || true
