#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TARGET="$(python3 - <<'PY'
import os
cand=[]
skip_dirs={".venv","out_ci","out","node_modules","__pycache__"}
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
    if "/api/vsp/run_file_allow" in s:
      cand.append(p)
print(cand[0] if cand else "")
PY
)"

[ -n "${TARGET:-}" ] || { echo "[ERR] cannot find '/api/vsp/run_file_allow' in code."; exit 2; }
W="$TARGET"
echo "[INFO] target file: $W"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${W}.bak_rfa_promote_${TS}"

python3 - "$W" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

TAG="VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2C"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

helper = f'''
# --- {TAG} ---
def __vsp_promote_findings_contract(j):
    """
    Ensure top-level findings is always a list (commercial contract).
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
# --- /{TAG} ---
'''

# insert helper after last import
m=list(re.finditer(r'(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$', s))
ins = m[-1].end() if m else 0
s = s[:ins] + "\n\n" + helper + "\n" + s[ins:]

# locate occurrence
idx = s.find("/api/vsp/run_file_allow")
if idx < 0:
    raise SystemExit("[ERR] cannot locate '/api/vsp/run_file_allow' string (unexpected)")

# find handler def AFTER idx
mdef = re.search(r'(?m)^def\s+([A-Za-z0-9_]+)\s*\(.*\)\s*:\s*$', s[idx:])
if not mdef:
    # maybe decorator block above; try search from a bit earlier
    start = max(0, idx - 2000)
    mdef = re.search(r'(?m)^def\s+([A-Za-z0-9_]+)\s*\(.*\)\s*:\s*$', s[start:])
    if not mdef:
        raise SystemExit("[ERR] cannot find handler def near route string")

def_start = (idx + mdef.start()) if (s[idx:idx+50] or True) and (mdef and s[idx:] == s[idx:]) else (start + mdef.start())
# fix def_start if we used 'start'
if def_start < 0:
    def_start = start + mdef.start()

# find function end (next top-level @app. or def)
nxt = re.search(r'(?m)^(?:@\s*app\.|def\s+)\b', s[def_start+1:])
def_end = (def_start+1 + nxt.start()) if nxt else len(s)
block = s[def_start:def_end]

# patch first "return jsonify(EXPR)" in that block
pat = r'(?m)^(?P<ind>\s*)return\s+(?P<jj>(?:flask\.)?jsonify)\(\s*(?P<expr>[^)]*?)\s*\)\s*$'
m = re.search(pat, block)
if not m:
    raise SystemExit("[ERR] cannot find 'return jsonify(...)' in handler block; patch aborted safely.")

ind = m.group("ind")
expr = m.group("expr").strip()

repl = (
    f"{ind}__j = {expr}\n"
    f"{ind}__j = __vsp_promote_findings_contract(__j)\n"
    f"{ind}resp = jsonify(__j)\n"
    f"{ind}resp.headers[\"X-VSP-RFA-PROMOTE\"] = \"v2\"\n"
    f"{ind}return resp"
)

block2 = re.sub(pat, repl, block, count=1)
s = s[:def_start] + block2 + s[def_end:]

open(p,"w",encoding="utf-8").write(s)
print("[OK] patched promote findings contract + header X-VSP-RFA-PROMOTE:v2")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
