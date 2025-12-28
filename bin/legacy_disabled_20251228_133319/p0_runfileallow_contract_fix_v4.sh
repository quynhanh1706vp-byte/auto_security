#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_contract_v4_${TS}"
echo "[BACKUP] ${W}.bak_contract_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# --- ensure helper exists
MARK_HELP = "VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1"
if MARK_HELP not in s:
    helper = r'''
# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
_DASHBOARD_ALLOW_EXACT = {
  "run_gate_summary.json",
  "findings_unified.json",
  "run_gate.json",
  "run_manifest.json",
  "run_evidence_index.json",
  "reports/findings_unified.csv",
  "reports/findings_unified.sarif",
  "reports/findings_unified.html",
}
def _dash_allow_exact(path: str) -> bool:
  try:
    p = (path or "").strip().lstrip("/")
    if not p: return False
    if ".." in p: return False
    if p.startswith(("/", "\\")): return False
    return p in _DASHBOARD_ALLOW_EXACT
  except Exception:
    return False
# ===================== /VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
'''
    m = re.search(r"^(import\s.+|from\s.+import\s.+)\n(?:import\s.+\n|from\s.+import\s.+\n)*", s, flags=re.M)
    if m:
        s = s[:m.end()] + helper + "\n" + s[m.end():]
    else:
        s = helper + "\n" + s

MARK_PATCH = "VSP_P0_RUNFILEALLOW_CONTRACT_V4"
if MARK_PATCH in s:
    p.write_text(s, encoding="utf-8")
    print("[OK] marker exists; skip")
    sys.exit(0)

lines = s.splitlines(True)

# --- locate route line
needle = "/api/vsp/run_file_allow"
route_i = next((i for i,l in enumerate(lines) if needle in l), None)
if route_i is None:
    # fallback: any decorator mentioning run_file_allow
    route_i = next((i for i,l in enumerate(lines) if "run_file_allow" in l and "api" in l), None)
if route_i is None:
    print("[ERR] cannot find run_file_allow route line")
    sys.exit(2)

# --- find handler def after route
def_i = None
for i in range(route_i, min(route_i+260, len(lines))):
    if re.match(r"^\s*def\s+\w+\s*\(", lines[i]):
        def_i = i
        break
if def_i is None:
    print("[ERR] cannot find handler def after route")
    sys.exit(2)

func_indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
func_indent_len = len(func_indent)

# --- find end of handler block
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    lj = lines[j]
    if lj.strip() == "":
        continue
    ind = len(re.match(r"^(\s*)", lj).group(1))
    if ind <= func_indent_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
        end_i = j
        break

handler = "".join(lines[def_i:end_i])

# --- detect path var name
pathvar = "path"
m = re.search(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", handler, flags=re.M)
if m:
    pathvar = m.group(1)

# --- find allow function usage inside handler
allow_fn = None

# pattern A: allowed = FUNC(path)
mA = re.search(r"^\s*allowed\s*=\s*([a-zA-Z_]\w*)\(\s*"+re.escape(pathvar)+r"\s*\)", handler, flags=re.M)
if mA:
    allow_fn = mA.group(1)

# pattern B: if not FUNC(path):
if allow_fn is None:
    mB = re.search(r"^\s*if\s+not\s+([a-zA-Z_]\w*)\(\s*"+re.escape(pathvar)+r"\s*\)\s*:", handler, flags=re.M)
    if mB:
        allow_fn = mB.group(1)

# pattern C: if not allowed: (then allow_fn unknown) -> patch allowed assignment later
# We'll try to patch the first allowed = <expr> line by ORing dash allow.

patched = False

def patch_allow_function(src: str, fn: str) -> str:
    # inject at top of def fn(path...) : if _dash_allow_exact(path): return True
    rx = re.compile(rf"^(\s*)def\s+{re.escape(fn)}\s*\(\s*([a-zA-Z_]\w*)", re.M)
    m = rx.search(src)
    if not m:
        return src
    indent = m.group(1)
    arg0 = m.group(2)
    # find insertion point: next line after def
    # ensure not already inserted
    head = f"{indent}def {fn}"
    start = m.start()
    # compute line start of def
    def_line_start = src.rfind("\n", 0, m.start()) + 1
    # insertion after def line
    def_line_end = src.find("\n", m.start())
    if def_line_end < 0:
        return src
    insert_at = def_line_end + 1
    inj = f"{indent}  # {MARK_PATCH}: dashboard contract bypass\n{indent}  if _dash_allow_exact({arg0}):\n{indent}    return True\n"
    if MARK_PATCH in src[def_line_start:insert_at+300]:
        return src
    return src[:insert_at] + inj + src[insert_at:]

if allow_fn:
    s2 = patch_allow_function(s, allow_fn)
    if s2 != s:
        s = s2
        patched = True
        print(f"[OK] patched allow function: {allow_fn}(...) pathvar={pathvar}")
    else:
        print(f"[WARN] could not locate def {allow_fn}(...) to patch")
else:
    print("[WARN] could not infer allow_fn from handler; will patch allowed assignment expression")

if not patched:
    # patch first allowed = ... line inside handler in file text (global), OR with dash allow
    # do it by rewriting within handler slice only
    handler_lines = lines[def_i:end_i]
    for k, l in enumerate(handler_lines):
        m = re.match(r"^(\s*)allowed\s*=\s*(.+)\s*$", l)
        if m and "_dash_allow_exact" not in l:
            indent = m.group(1)
            expr = m.group(2).rstrip()
            handler_lines[k] = f"{indent}allowed = ({expr}) or _dash_allow_exact({pathvar})  # {MARK_PATCH}\n"
            patched = True
            print(f"[OK] patched handler allowed assignment; pathvar={pathvar}")
            break
    if patched:
        lines[def_i:end_i] = handler_lines
        s = "".join(lines)

if not patched:
    # last resort: insert early line after pathvar assignment
    handler_lines = lines[def_i:end_i]
    inserted = False
    rx = re.compile(r"^\s*"+re.escape(pathvar)+r"\s*=\s*request\.args\.get\(\s*['\"]path['\"]", re.M)
    for k, l in enumerate(handler_lines):
        if rx.search(l):
            indent = re.match(r"^(\s*)", l).group(1)
            ins = f"{indent}# {MARK_PATCH}: early bypass flag\n{indent}__vsp_dash_contract_ok = _dash_allow_exact({pathvar})\n"
            handler_lines.insert(k+1, ins)
            inserted = True
            break
    if inserted:
        lines[def_i:end_i] = handler_lines
        s = "".join(lines)
        patched = True
        print("[OK] inserted early bypass flag (no allowed rewrite found)")

if not patched:
    print("[ERR] no patch applied; need manual inspect handler patterns")
    sys.exit(2)

p.write_text(s, encoding="utf-8")
print("[OK] wrote patch")
PY

echo "== py_compile =="
python3 -m py_compile "$W"

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
