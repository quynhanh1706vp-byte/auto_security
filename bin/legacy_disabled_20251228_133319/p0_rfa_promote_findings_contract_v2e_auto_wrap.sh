#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TAG="VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2E"

TARGET="$(python3 - <<'PY'
import os
skip_dirs={".venv","out_ci","out","node_modules","__pycache__"}
cands=[]
for root,dirs,files in os.walk("."):
  dirs[:] = [d for d in dirs if d not in skip_dirs and not d.startswith(".")]
  for fn in files:
    if not fn.endswith(".py"): continue
    if ".bak_" in fn or ".disabled_" in fn: continue
    p=os.path.join(root,fn)
    try:
      s=open(p,"r",encoding="utf-8",errors="replace").read()
    except Exception:
      continue
    # ưu tiên file có function name
    if "def vsp_run_file_allow_v5" in s:
      print(p); raise SystemExit
    # fallback theo route string
    if "/api/vsp/run_file_allow" in s:
      cands.append(p)
print(cands[0] if cands else "")
PY
)"

[ -n "${TARGET:-}" ] || { echo "[ERR] cannot locate vsp_run_file_allow_v5 or /api/vsp/run_file_allow in code"; exit 2; }
W="$TARGET"
echo "[INFO] target file: $W"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${W}.bak_rfa_promote_${TS}"

python3 - "$W" "$TAG" <<'PY'
import sys, re
p=sys.argv[1]
TAG=sys.argv[2]
s=open(p,"r",encoding="utf-8",errors="replace").read()

if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

helpers = f'''
# --- {TAG} ---
try:
    from flask import jsonify
except Exception:
    jsonify = None

def __vsp_promote_findings_contract(j):
    """
    Commercial contract: top-level findings must be a list.
    Promotion order:
      findings -> items -> data(list) -> data.findings/items/data (nested)
    """
    try:
        if not isinstance(j, dict):
            return j
        f = j.get("findings")
        if isinstance(f, list) and f:
            return j

        cands = []
        it = j.get("items")
        if isinstance(it, list) and it:
            cands = it

        dt = j.get("data")
        if not cands and isinstance(dt, list) and dt:
            cands = dt

        if not cands and isinstance(dt, dict):
            for k in ("findings","items","data"):
                v = dt.get(k)
                if isinstance(v, list) and v:
                    cands = v
                    break

        j["findings"] = cands if isinstance(cands, list) else []
    except Exception:
        try:
            if isinstance(j, dict) and "findings" not in j:
                j["findings"] = []
        except Exception:
            pass
    return j

def __vsp_rfa_finalize(ret):
    """
    Wrap returns safely:
      - dict -> promote + jsonify + header
      - (resp, code, ...) -> finalize resp then keep code
      - Response-like -> only set header
    """
    try:
        if isinstance(ret, tuple) and ret:
            head = __vsp_rfa_finalize(ret[0])
            return (head, *ret[1:])

        if isinstance(ret, dict):
            ret = __vsp_promote_findings_contract(ret)
            if jsonify is not None:
                resp = jsonify(ret)
                try:
                    resp.headers["X-VSP-RFA-PROMOTE"] = "v2"
                except Exception:
                    pass
                return resp
            return ret

        if hasattr(ret, "headers"):
            try:
                ret.headers["X-VSP-RFA-PROMOTE"] = "v2"
            except Exception:
                pass
            return ret
    except Exception:
        pass
    return ret
# --- /{TAG} ---
'''

# insert helpers after last import
m=list(re.finditer(r'(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$', s))
ins = m[-1].end() if m else 0
s = s[:ins] + "\n\n" + helpers + "\n" + s[ins:]

# locate function block to patch
mdef = re.search(r'(?m)^def\s+vsp_run_file_allow_v5\s*\(.*\)\s*:\s*$', s)
if not mdef:
    # fallback: find route string then next def
    idx = s.find("/api/vsp/run_file_allow")
    if idx < 0:
        raise SystemExit("[ERR] cannot find vsp_run_file_allow_v5 nor route string")
    mdef = re.search(r'(?m)^def\s+\w+\s*\(.*\)\s*:\s*$', s[idx:])
    if not mdef:
        raise SystemExit("[ERR] cannot find handler def after route string")
    fn_start = idx + mdef.start()
else:
    fn_start = mdef.start()

# function end at next top-level def
nxt = re.search(r'(?m)^def\s+\w+\s*\(.*\)\s*:\s*$', s[fn_start+1:])
fn_end = (fn_start+1 + nxt.start()) if nxt else len(s)

block = s[fn_start:fn_end]
if "__vsp_rfa_finalize(" in block:
    raise SystemExit("[OK] already wrapped returns in handler")

def repl(m):
    ind=m.group("ind")
    expr=m.group("expr").rstrip()
    if "__vsp_rfa_finalize" in expr:
        return m.group(0)
    return f"{ind}return __vsp_rfa_finalize({expr})"

block2 = re.sub(r'(?m)^(?P<ind> {4})return\s+(?P<expr>.+)$', repl, block)
if block2 == block:
    raise SystemExit("[ERR] no indent-4 return lines found to wrap; safe abort")

s = s[:fn_start] + block2 + s[fn_end:]
open(p,"w",encoding="utf-8").write(s)
print("[OK] patched + wrapped returns -> X-VSP-RFA-PROMOTE:v2")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
