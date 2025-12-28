#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_fix_overall_runsv3_v4_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK = "VSP_P1_FIX_OVERALL_RUNS_V3_WRAPPER_RETURN_V4"
if MARK in s:
    print("[SKIP] already patched:", MARK)
    raise SystemExit(0)

lines = s.splitlines(True)

# 1) find handler function name for /api/ui/runs_v3
src = "".join(lines)
fn_name = None

m = re.search(r'add_url_rule\([^)]*/api/ui/runs_v3[^)]*view_func\s*=\s*([A-Za-z_]\w*)', src)
if m: fn_name = m.group(1)

if not fn_name:
    # decorator style: find /api/ui/runs_v3 then nearest def
    idx = None
    for i, ln in enumerate(lines):
        if "/api/ui/runs_v3" in ln and ("route" in ln or "get(" in ln):
            idx = i
            break
    if idx is not None:
        for j in range(idx, min(idx+15, len(lines))):
            mm = re.match(r'^\s*def\s+([A-Za-z_]\w*)\s*\(', lines[j])
            if mm:
                fn_name = mm.group(1)
                break

if not fn_name:
    # fallback: your known wrapper name pattern
    for ln in lines:
        mm = re.match(r'^\s*def\s+([A-Za-z_]\w*runs_v3[A-Za-z_]\w*)\s*\(', ln)
        if mm:
            fn_name = mm.group(1)
            break

if not fn_name:
    print("[ERR] cannot determine runs_v3 handler function")
    raise SystemExit(2)

print("[OK] runs_v3 handler =", fn_name)

# 2) insert helper after last import
helper = f"""
# {MARK}
import json as _vsp_json

def _vsp_safe_int(v, default=0):
    try:
        return int(v) if v is not None else default
    except Exception:
        return default

def _vsp_infer_overall_from_counts(counts: dict, total: int = 0) -> str:
    counts = counts or {{}}
    c = _vsp_safe_int(counts.get("CRITICAL") or counts.get("critical"), 0)
    h = _vsp_safe_int(counts.get("HIGH") or counts.get("high"), 0)
    m = _vsp_safe_int(counts.get("MEDIUM") or counts.get("medium"), 0)
    l = _vsp_safe_int(counts.get("LOW") or counts.get("low"), 0)
    i = _vsp_safe_int(counts.get("INFO") or counts.get("info"), 0)
    t = _vsp_safe_int(counts.get("TRACE") or counts.get("trace"), 0)
    tot = _vsp_safe_int(total, 0)
    if c > 0 or h > 0: return "RED"
    if m > 0: return "AMBER"
    if tot > 0 or (l+i+t) > 0: return "GREEN"
    return "GREEN"

def _vsp_apply_overall_inference_on_payload(payload: dict):
    items = payload.get("items")
    if not isinstance(items, list): return payload
    for it in items:
        if not isinstance(it, dict): 
            continue
        has_gate = bool(it.get("has_gate"))
        overall  = (it.get("overall") or "").strip().upper()
        counts   = it.get("counts") or {{}}
        total    = it.get("findings_total") or it.get("total") or 0
        inferred = _vsp_infer_overall_from_counts(counts, total)
        it["overall_inferred"] = inferred
        if has_gate and overall and overall != "UNKNOWN":
            it["overall_source"] = "gate"
        else:
            if (not overall) or overall == "UNKNOWN":
                it["overall"] = inferred
            it["overall_source"] = "inferred_counts"
    return payload

def _vsp_patch_runs_v3_return(x):
    # x can be: dict, (body,status,headers), Flask Response-like, or anything else
    try:
        # tuple response
        if isinstance(x, tuple) and len(x) >= 1:
            body = x[0]
            rest = x[1:]
            if isinstance(body, dict) and isinstance(body.get("items"), list):
                _vsp_apply_overall_inference_on_payload(body)
                return (body, *rest)
            return x

        # dict payload
        if isinstance(x, dict) and isinstance(x.get("items"), list):
            _vsp_apply_overall_inference_on_payload(x)
            return x

        # Response-like (Flask)
        if hasattr(x, "get_data") and hasattr(x, "set_data"):
            ct = ""
            try:
                ct = (getattr(x, "content_type", "") or "") + " " + (x.headers.get("Content-Type","") if hasattr(x, "headers") else "")
            except Exception:
                ct = ""
            if "application/json" in ct:
                raw = x.get_data(as_text=True) or ""
                if raw.strip():
                    obj = _vsp_json.loads(raw)
                    if isinstance(obj, dict) and isinstance(obj.get("items"), list):
                        _vsp_apply_overall_inference_on_payload(obj)
                        new_raw = _vsp_json.dumps(obj, ensure_ascii=False)
                        x.set_data(new_raw)
                        try:
                            x.headers["Content-Length"] = str(len(new_raw.encode("utf-8")))
                        except Exception:
                            pass
            return x
    except Exception:
        return x
    return x
""".lstrip("\n")

last_imp = 0
for i, ln in enumerate(lines):
    if re.match(r'^\s*(from\s+\S+\s+import|import\s+\S+)', ln):
        last_imp = i+1
lines.insert(last_imp, "\n" + helper + "\n")

# 3) locate def block by indentation tracking
def_line = None
for i, ln in enumerate(lines):
    if re.match(rf'^\s*def\s+{re.escape(fn_name)}\s*\(', ln):
        def_line = i
        break
if def_line is None:
    print("[ERR] cannot locate def line for", fn_name)
    raise SystemExit(3)

def_indent = len(lines[def_line]) - len(lines[def_line].lstrip(" "))
end = len(lines)
for k in range(def_line+1, len(lines)):
    t = lines[k].strip()
    if not t:
        continue
    ind = len(lines[k]) - len(lines[k].lstrip(" "))
    if ind <= def_indent and (t.startswith("@") or t.startswith("def ") or t.startswith("class ") or re.match(r'^\w', t)):
        end = k
        break

body = lines[def_line:end]

# 4) hook the FIRST simple "return <expr>" inside wrapper (single line)
patched = False
for i, ln in enumerate(body):
    mret = re.match(r'^(\s*)return\s+(.+?)\s*$', ln)
    if not mret:
        continue
    indent = mret.group(1)
    expr = mret.group(2)

    # avoid patching "return" in nested defs? Here we only operate in this def block; fine.
    hook = (
        f"{indent}# {MARK}_HOOK\n"
        f"{indent}__vsp__ret = ({expr})\n"
        f"{indent}try:\n"
        f"{indent}    __vsp__ret = _vsp_patch_runs_v3_return(__vsp__ret)\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
        f"{indent}return __vsp__ret\n"
    )
    body[i] = hook
    patched = True
    print("[OK] hooked return line:", ln.strip()[:120])
    break

if not patched:
    print("[ERR] cannot find a single-line return statement to hook inside", fn_name)
    raise SystemExit(4)

lines[def_line:end] = body
p.write_text("".join(lines), encoding="utf-8")
print("[OK] wrote patched file:", p)
PY

# transactional compile: fail => restore backup, exit
if ! python3 -m py_compile wsgi_vsp_ui_gateway.py; then
  echo "[ERR] py_compile failed -> restore $BAK"
  cp -f "$BAK" wsgi_vsp_ui_gateway.py
  python3 -m py_compile wsgi_vsp_ui_gateway.py || true
  exit 3
fi
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== verify =="
ss -ltnp | egrep '(:8910)' || true
RAW="$(curl -sS "$BASE/api/ui/runs_v3?limit=3" || true)"
python3 - <<PY
import json,sys
raw = """$RAW"""
if not raw.strip():
    print("[ERR] empty response from runs_v3")
    sys.exit(2)
d=json.loads(raw)
for it in (d.get("items") or [])[:3]:
    print(it.get("rid"), it.get("has_gate"), it.get("overall"), it.get("overall_source"), it.get("overall_inferred"))
PY
