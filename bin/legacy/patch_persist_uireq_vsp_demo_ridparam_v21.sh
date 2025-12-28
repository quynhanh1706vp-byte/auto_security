#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v21_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v21_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_PERSIST_RIDPARAM_V21" in txt:
    print("[OK] already patched V21.")
    raise SystemExit(0)

# Ensure V19 helper exists (needed: _vsp_append_v19, _vsp_uireq_update_v19, constants)
if "VSP_UIREQ_PERSIST_ROUTE_V19" not in txt:
    print("[ERR] V19 helper not found in vsp_demo_app.py; run v19 route patch first.")
    raise SystemExit(2)

v21 = r'''
# === VSP_PERSIST_RIDPARAM_V21 ===
def _vsp_payload_from_ret_v21(retval):
    """Extract dict payload from return value (dict | tuple | flask.Response | json string)."""
    try:
        base = retval
        if isinstance(retval, tuple) and len(retval) >= 1:
            base = retval[0]

        if isinstance(base, dict):
            return base

        if hasattr(base, "get_json"):
            try:
                j = base.get_json(silent=True)
                if isinstance(j, dict):
                    return j
            except Exception:
                pass

        # try response.data / get_data
        if hasattr(base, "get_data"):
            try:
                s = base.get_data(as_text=True)
                if isinstance(s, str):
                    s2 = s.strip()
                    if s2.startswith("{") and s2.endswith("}"):
                        try:
                            j = _json.loads(s2)
                            if isinstance(j, dict):
                                return j
                        except Exception:
                            pass
            except Exception:
                pass

        # raw string json
        if isinstance(base, (str, bytes, bytearray)):
            s = base.decode("utf-8", "ignore") if isinstance(base, (bytes, bytearray)) else base
            s2 = s.strip()
            if s2.startswith("{") and s2.endswith("}"):
                try:
                    j = _json.loads(s2)
                    if isinstance(j, dict):
                        return j
                except Exception:
                    pass
        return None
    except Exception:
        return None

def _vsp_persist_ret_with_rid_v21(rid: str, retval):
    """Persist using rid from URL no matter payload contains req_id or not."""
    try:
        _vsp_append_v19(_VSP_HIT_LOG_V19, f"persist_v21 ts={_time.time()} file={__file__} rid={rid} type={type(retval)}")
        payload = _vsp_payload_from_ret_v21(retval)
        if not isinstance(payload, dict):
            payload = {"ok": True, "req_id": rid}

        # enforce req_id
        payload["req_id"] = payload.get("req_id") or rid

        _vsp_uireq_update_v19(str(rid), payload)
    except Exception as e:
        try:
            _vsp_append_v19(_VSP_ERR_LOG_V19, f"persist_v21_fail rid={rid} err={repr(e)} file={__file__}")
            _vsp_append_v19(_VSP_ERR_LOG_V19, _traceback.format_exc())
        except Exception:
            pass
    return retval
# === END VSP_PERSIST_RIDPARAM_V21 ===
'''.lstrip("\n")

# Insert V21 helpers right after V20 block end if exists, else after V19 end
m = re.search(r'# === END VSP_PERSIST_ANY_V20 ===\s*', txt)
if m:
    txt = txt[:m.end()] + "\n" + v21 + "\n" + txt[m.end():]
else:
    m2 = re.search(r'# === END VSP_UIREQ_PERSIST_ROUTE_V19 ===\s*', txt)
    if m2:
        txt = txt[:m2.end()] + "\n" + v21 + "\n" + txt[m2.end():]
    else:
        txt = v21 + "\n" + txt

lines = txt.splitlines(True)

# Find route decorator line
route_idx = None
for i, ln in enumerate(lines):
    if "/api/vsp/run_status_v1" in ln:
        route_idx = i
        break
if route_idx is None:
    print("[ERR] cannot find /api/vsp/run_status_v1 in vsp_demo_app.py")
    raise SystemExit(3)

# Find next def after decorator
def_idx = None
for j in range(route_idx, min(route_idx + 300, len(lines))):
    if re.match(r'^\s*def\s+\w+\s*\((?P<args>[^\)]*)\)\s*:\s*$', lines[j]):
        def_idx = j
        break
if def_idx is None:
    print("[ERR] cannot find def after route decorator in vsp_demo_app.py")
    raise SystemExit(4)

mdef = re.match(r'^\s*def\s+\w+\s*\((?P<args>[^\)]*)\)\s*:\s*$', lines[def_idx])
args = (mdef.group("args") or "").strip()

# Determine rid param name: first non-self param
rid_param = None
if args:
    parts = [x.strip() for x in args.split(",") if x.strip()]
    for x in parts:
        name = x.split("=")[0].strip()
        if name != "self":
            rid_param = name
            break
if not rid_param:
    rid_param = "req_id"  # fallback

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

# Wrap every single-line return in this function: return X -> return _vsp_persist_ret_with_rid_v21(<rid_param>, X)
patched = 0
for k in range(def_idx + 1, end):
    ln = lines[k]
    mret = re.match(r'^(\s*)return\s+(.+?)\s*$', ln)
    if not mret:
        continue
    expr = mret.group(2)

    # skip multiline continuations
    if expr.endswith("\\") or expr.endswith("(") or expr.endswith("[") or expr.endswith("{"):
        continue

    # Already wrapped?
    if "_vsp_persist_ret_with_rid_v21" in expr:
        continue

    # If wrapped by V20 wrapper, unwrap by taking inner expr
    mm = re.match(r'_vsp_persist_from_return_v20\((.+)\)$', expr.strip())
    if mm:
        expr = mm.group(1).strip()

    indent = mret.group(1)
    lines[k] = f"{indent}return _vsp_persist_ret_with_rid_v21({rid_param}, {expr})\n"
    patched += 1

# Add an entry log at function start
body_indent = re.match(r'^(\s*)', lines[def_idx+1]).group(1) if def_idx+1 < len(lines) else (" " * (def_indent + 2))
entry = body_indent + f'_vsp_append_v19(_VSP_HIT_LOG_V19, f"enter_v21 ts={{_time.time()}} file={{__file__}} ridparam={rid_param}")\n'
lines.insert(def_idx+1, entry)

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] V21 patched handler returns={patched} rid_param={rid_param} def_line={def_idx}")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile passed"
grep -n "VSP_PERSIST_RIDPARAM_V21" "$F" | head -n 80 || true
