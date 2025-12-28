#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

TARGET="$(python3 - <<'PY'
import os, re
cand=[]
for root,_,files in os.walk("."):
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

if [ -z "${TARGET:-}" ]; then
  echo "[ERR] cannot find '/api/vsp/run_file_allow' in any .py file."
  echo "Try:"
  echo "  grep -RIn --exclude='*.bak_*' -E '(/api/vsp/run_file_allow|run_file_allow)' . | head"
  exit 2
fi

W="$TARGET"
echo "[INFO] target file: $W"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${W}.bak_rfa_promote_${TS}"

python3 - "$W" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

TAG="VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2B"

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

# insert helper after imports
m=list(re.finditer(r'(?m)^(from\\s+\\S+\\s+import\\s+.+|import\\s+\\S+.*)\\s*$', s))
ins = m[-1].end() if m else 0
s = s[:ins] + "\\n\\n" + helper + "\\n" + s[ins:]

# locate route decorator (flexible)
dec = re.search(r'@\\s*app\\.(?:route|get|post)\\(\\s*[\\\'"]\\/api\\/vsp\\/run_file_allow[\\\'"]', s)
if not dec:
    raise SystemExit("[ERR] cannot locate decorator for /api/vsp/run_file_allow (maybe registered via add_url_rule/blueprint).")

# find handler def after decorator
after = s[dec.end():]
fn = re.search(r'(?m)^def\\s+([a-zA-Z0-9_]+)\\s*\\(.*\\)\\s*:\\s*$', after)
if not fn:
    raise SystemExit("[ERR] cannot locate handler def after decorator")

fn_start = dec.end() + fn.start()
# function block end = next top-level decorator/def
nxt = re.search(r'(?m)^(?:@\\s*app\\.|def\\s+)\\b', s[fn_start+1:])
fn_end = (fn_start+1 + nxt.start()) if nxt else len(s)
block = s[fn_start:fn_end]

# replace first return jsonify(EXPR)
pat = r'(?m)^(?P<ind>\\s*)return\\s+(?P<jj>(?:flask\\.)?jsonify)\\(\\s*(?P<expr>[^\\)]+?)\\s*\\)\\s*$'
m = re.search(pat, block)
if not m:
    raise SystemExit("[ERR] cannot find 'return jsonify(...)' in handler; patch aborted safely.")

ind = m.group("ind")
expr = m.group("expr").strip()

repl = (
    f"{ind}__j = {expr}\\n"
    f"{ind}__j = __vsp_promote_findings_contract(__j)\\n"
    f"{ind}resp = jsonify(__j)\\n"
    f"{ind}resp.headers[\"X-VSP-RFA-PROMOTE\"] = \"v2\"\\n"
    f"{ind}return resp"
)

block2 = re.sub(pat, repl, block, count=1)
s = s[:fn_start] + block2 + s[fn_end:]

open(p,"w",encoding="utf-8").write(s)
print("[OK] patched promote findings contract + header X-VSP-RFA-PROMOTE:v2")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
