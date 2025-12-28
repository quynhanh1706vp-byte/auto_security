#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_promote_${TS}"
echo "[BACKUP] ${W}.bak_rfa_promote_${TS}"

python3 - "$W" <<'PY'
import sys, re
p=sys.argv[1]
s=open(p,"r",encoding="utf-8",errors="replace").read()

TAG="VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

# 1) Add helper near top (after imports block best-effort)
helper = r'''
# --- VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2 ---
def __vsp_promote_findings_contract(j):
    """
    Normalize run_file_allow JSON so UI/commercial contract always has:
      - top-level findings: list
    Promotion order:
      findings -> items -> data (list) -> data.findings/items/data (nested)
    """
    try:
        if not isinstance(j, dict):
            return j
        f = j.get("findings")
        if isinstance(f, list) and len(f) > 0:
            return j

        # candidates
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

        if cands is None:
            cands = []
        if isinstance(cands, list):
            j["findings"] = cands
        else:
            j["findings"] = []
    except Exception:
        try:
            if isinstance(j, dict) and "findings" not in j:
                j["findings"] = []
        except Exception:
            pass
    return j
# --- /VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2 ---
'''

# Place helper after last import if possible
m=list(re.finditer(r'(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$', s))
if m:
    ins = m[-1].end()
    s = s[:ins] + "\n\n" + helper + "\n" + s[ins:]
else:
    s = helper + "\n" + s

# 2) Patch the /api/vsp/run_file_allow handler: replace "return jsonify(j)" to wrapper with header + promote.
# Locate decorator
dec = re.search(r'@app\.route\(\s*[\'"]\/api\/vsp\/run_file_allow[\'"]', s)
if not dec:
    raise SystemExit("[ERR] cannot locate /api/vsp/run_file_allow decorator")

# Find function start after decorator
fn = re.search(r'(?m)^def\s+([a-zA-Z0-9_]+)\s*\(.*\)\s*:\s*$', s[dec.end():])
if not fn:
    raise SystemExit("[ERR] cannot locate handler def after decorator")

fn_start = dec.end() + fn.start()
fn_name = re.search(r'^def\s+([a-zA-Z0-9_]+)\s*\(', s[fn_start:], flags=re.M).group(1)

# Determine function block end by next top-level decorator/def with same indent (assume indent 0)
after = s[fn_start:]
# find next "\n@app.route" or "\ndef " at col 0 (skip first def)
nxt = re.search(r'(?m)^(?:@app\.route\(|def\s+)\b', after.splitlines(True)[1] and after[1:] or after)
# safer: search from fn_start+1
nxt = re.search(r'(?m)^(?:@app\.route\(|def\s+)\b', s[fn_start+1:])
fn_end = (fn_start+1 + nxt.start()) if nxt else len(s)

block = s[fn_start:fn_end]

# If block already has __vsp_promote_findings_contract call, skip
if "__vsp_promote_findings_contract" not in block:
    # Replace "return jsonify(j)" with:
    # j = __vsp_promote_findings_contract(j)
    # resp = jsonify(j); resp.headers["X-VSP-RFA-PROMOTE"]="v2"; return resp
    pat = r'(?m)^\s*return\s+jsonify\(\s*j\s*\)\s*$'
    if re.search(pat, block):
        repl = (
            "    j = __vsp_promote_findings_contract(j)\n"
            "    resp = jsonify(j)\n"
            "    resp.headers[\"X-VSP-RFA-PROMOTE\"] = \"v2\"\n"
            "    return resp"
        )
        block2 = re.sub(pat, repl, block, count=1)
    else:
        # fallback: before any "return" at end, inject a promote+header wrapper if we can spot "jsonify("
        pat2 = r'(?m)^(?P<ind>\s*)resp\s*=\s*jsonify\(\s*j\s*\)\s*$'
        if re.search(pat2, block):
            block2 = re.sub(pat2,
                r'\g<ind>j = __vsp_promote_findings_contract(j)\n\g<ind>resp = jsonify(j)\n\g<ind>resp.headers["X-VSP-RFA-PROMOTE"]="v2"',
                block, count=1)
        else:
            raise SystemExit("[ERR] cannot locate return jsonify(j) or resp=jsonify(j) in handler; patch aborted")
    s = s[:fn_start] + block2 + s[fn_end:]

# tag marker
s = s.replace("# --- VSP_P0_RFA_PROMOTE_FINDINGS_CONTRACT_V2 ---", f"# --- {TAG} ---", 1)

open(p,"w",encoding="utf-8").write(s)
print("[OK] patched run_file_allow to promote findings + set X-VSP-RFA-PROMOTE:v2")
print("[OK] handler =", fn_name)
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"
