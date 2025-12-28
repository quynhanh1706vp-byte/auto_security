#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="vsp_demo_app.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${W}.bak_rfa_promote_${TS}"

python3 - "$W" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

TAG="VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2D"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

# --- helpers to insert after imports ---
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
        # tuple return
        if isinstance(ret, tuple) and ret:
            head = __vsp_rfa_finalize(ret[0])
            return (head, *ret[1:])

        # dict -> jsonify
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

        # Response-like: set header only
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

# locate function vsp_run_file_allow_v5
mdef = re.search(r'(?m)^def\s+vsp_run_file_allow_v5\s*\(.*\)\s*:\s*$', s)
if not mdef:
    raise SystemExit("[ERR] cannot find def vsp_run_file_allow_v5(...)")

fn_start = mdef.start()
# end at next top-level def
nxt = re.search(r'(?m)^def\s+\w+\s*\(.*\)\s*:\s*$', s[mdef.end():])
fn_end = (mdef.end() + nxt.start()) if nxt else len(s)

block = s[fn_start:fn_end]

if "__vsp_rfa_finalize(" in block:
    raise SystemExit("[OK] already wrapped returns in vsp_run_file_allow_v5")

# replace returns at indent 4 spaces only (avoid nested defs)
def repl(m):
    ind=m.group("ind")
    expr=m.group("expr").rstrip()
    if "__vsp_rfa_finalize" in expr:
        return m.group(0)
    return f"{ind}return __vsp_rfa_finalize({expr})"

block2 = re.sub(r'(?m)^(?P<ind> {4})return\s+(?P<expr>.+)$', repl, block)

if block2 == block:
    raise SystemExit("[ERR] no matching 'return ...' lines at indent 4; patch aborted safely.")

s = s[:fn_start] + block2 + s[fn_end:]
open(p,"w",encoding="utf-8").write(s)
print("[OK] wrapped returns in vsp_run_file_allow_v5 -> __vsp_rfa_finalize()")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
