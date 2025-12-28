#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v20_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v20_${TS}"

python3 - "$F" <<'PY'
import re, sys, json
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PERSIST_ANY_V20" in txt:
    print("[OK] already patched V20.")
    raise SystemExit(0)

# Ensure V19 helper exists; if not, insert a minimal helper (reusing V19 names if present).
if "VSP_UIREQ_PERSIST_ROUTE_V19" not in txt:
    helper = r'''
# === VSP_UIREQ_PERSIST_ROUTE_V19 ===
import os as _os
import json as _json
import time as _time
import traceback as _traceback

_VSP_UIREQ_DIR_V19 = "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1"
_VSP_HIT_LOG_V19   = _VSP_UIREQ_DIR_V19 + "/_persist_hits.log"
_VSP_ERR_LOG_V19   = _VSP_UIREQ_DIR_V19 + "/_persist_err.log"

def _vsp_append_v19(path, line):
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V19, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:
        pass

def _vsp_uireq_update_v19(rid: str, payload: dict):
    fp = _VSP_UIREQ_DIR_V19 + f"/{rid}.json"
    try:
        _os.makedirs(_VSP_UIREQ_DIR_V19, exist_ok=True)
        try:
            cur = _json.loads(open(fp, "r", encoding="utf-8").read())
        except Exception:
            cur = {"ok": True, "req_id": rid}

        if not isinstance(payload, dict):
            payload = {}

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
        _vsp_append_v19(_VSP_ERR_LOG_V19, f"update_fail rid={rid} err={repr(e)} file={__file__}")
        _vsp_append_v19(_VSP_ERR_LOG_V19, _traceback.format_exc())
        return False
# === END VSP_UIREQ_PERSIST_ROUTE_V19 ===
'''.lstrip("\n")

    m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
    if m:
        txt = txt[:m.end()] + "\n" + helper + "\n" + txt[m.end():]
    else:
        ls = txt.splitlines(True)
        txt = "".join(ls[:1]) + "\n" + helper + "\n" + "".join(ls[1:])

# Insert V20 helper (parse + persist-any)
v20 = r'''
# === VSP_PERSIST_ANY_V20 ===
def _vsp_extract_payload_v20(obj):
    """Try to get a dict payload from (dict | (obj,code,headers) | flask.Response | str/bytes json)."""
    try:
        base = obj
        if isinstance(obj, tuple) and len(obj) >= 1:
            base = obj[0]

        if isinstance(base, dict):
            return base

        # flask Response
        if hasattr(base, "get_json"):
            try:
                j = base.get_json(silent=True)
                if isinstance(j, dict):
                    return j
            except Exception:
                pass

        # raw text/json
        if isinstance(base, (str, bytes, bytearray)):
            s = base.decode("utf-8", "ignore") if isinstance(base, (bytes, bytearray)) else base
            s = s.strip()
            if s.startswith("{") and s.endswith("}"):
                try:
                    j = _json.loads(s)
                    if isinstance(j, dict):
                        return j
                except Exception:
                    pass
        return None
    except Exception:
        return None

def _vsp_persist_from_return_v20(retval):
    try:
        payload = _vsp_extract_payload_v20(retval)
        if isinstance(payload, dict):
            rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
            if rid:
                _vsp_uireq_update_v19(str(rid), payload)
    except Exception as e:
        try:
            _vsp_append_v19(_VSP_ERR_LOG_V19, f"persist_from_return_fail err={repr(e)} file={__file__}")
        except Exception:
            pass
    return retval
# === END VSP_PERSIST_ANY_V20 ===
'''.lstrip("\n")

if "VSP_PERSIST_ANY_V20" not in txt:
    # place after the V19 helper end if exists
    m2 = re.search(r'# === END VSP_UIREQ_PERSIST_ROUTE_V19 ===\s*', txt)
    if m2:
        txt = txt[:m2.end()] + "\n" + v20 + "\n" + txt[m2.end():]
    else:
        txt = v20 + "\n" + txt

lines = txt.splitlines(True)

# Locate route decorator line for /api/vsp/run_status_v1
route_idx = None
for i, ln in enumerate(lines):
    if "/api/vsp/run_status_v1" in ln:
        route_idx = i
        break
if route_idx is None:
    print("[ERR] cannot find /api/vsp/run_status_v1 in vsp_demo_app.py")
    raise SystemExit(2)

# Find next def after decorator
def_idx = None
for j in range(route_idx, min(route_idx + 250, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\(.*\)\s*:\s*$', lines[j]):
        def_idx = j
        break
if def_idx is None:
    print("[ERR] cannot find def after route decorator in vsp_demo_app.py")
    raise SystemExit(3)

def_indent = len(lines[def_idx]) - len(lines[def_idx].lstrip(" \t"))

# Find function end
end = len(lines)
for k in range(def_idx + 1, len(lines)):
    ln = lines[k]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = k
        break

# Wrap ALL single-line returns in this function: `return X` -> `return _vsp_persist_from_return_v20(X)`
patched = 0
for k in range(def_idx+1, end):
    ln = lines[k]
    if "VSP_PERSIST_ANY_V20" in ln:
        continue
    mret = re.match(r'^(\s*)return\s+(.+?)\s*$', ln)
    if not mret:
        continue
    expr = mret.group(2)
    # skip dangerous multi-line / continuation
    if expr.endswith("\\") or expr.endswith("(") or expr.endswith("[") or expr.endswith("{"):
        continue
    # already wrapped?
    if "_vsp_persist_from_return_v20" in expr:
        continue
    indent = mret.group(1)
    lines[k] = f"{indent}return _vsp_persist_from_return_v20({expr})\n"
    patched += 1

# Also log entry to hits (prove handler active)
body_indent = re.match(r'^(\s*)', lines[def_idx+1]).group(1) if def_idx+1 < len(lines) else (" " * (def_indent + 2))
entry = body_indent + '_vsp_append_v19(_VSP_HIT_LOG_V19, f"enter_v20 ts={_time.time()} file={__file__} route=/api/vsp/run_status_v1")\n'
lines.insert(def_idx+1, entry)

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] V20 wrapped returns in handler: patched_returns={patched}, def_line={def_idx}")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile passed"
grep -n "VSP_PERSIST_ANY_V20" "$F" | head -n 60 || true
