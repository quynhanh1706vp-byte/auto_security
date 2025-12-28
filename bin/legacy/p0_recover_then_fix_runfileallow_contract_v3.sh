#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.broken_${TS}"
echo "[SNAPSHOT] ${W}.broken_${TS}"

echo "== find latest compiling backup =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile, sys

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for p in baks:
    try:
        py_compile.compile(str(p), doraise=True)
        print(str(p))
        sys.exit(0)
    except Exception:
        continue
print("")
sys.exit(1)
PY
)" || true

if [ -z "${GOOD:-}" ]; then
  echo "[ERR] no compiling backup found. List backups:"
  ls -1 wsgi_vsp_ui_gateway.py.bak_* 2>/dev/null || true
  exit 2
fi

echo "[OK] restore from $GOOD"
cp -f "$GOOD" "$W"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK_HELP = "VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1"
if MARK_HELP not in s:
    block = r'''
# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
# Dashboard minimal whitelist (exact paths; no glob)
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
        s = s[:m.end()] + block + "\n" + s[m.end():]
    else:
        s = block + "\n" + s

MARK_PATCH = "VSP_P0_RUNFILEALLOW_FORCE_CONTRACT_IN_HANDLER_V3"
if MARK_PATCH in s:
    p.write_text(s, encoding="utf-8")
    print("[OK] handler already patched")
    sys.exit(0)

# locate handler area
needle = "/api/vsp/run_file_allow"
pos = s.find(needle)
if pos < 0:
    pos = s.find("run_file_allow")
if pos < 0:
    print("[ERR] cannot locate run_file_allow area")
    sys.exit(2)

lines = s.splitlines(True)
# find line index that contains the route string
route_i = next((i for i,l in enumerate(lines) if needle in l), None)
if route_i is None:
    route_i = next((i for i,l in enumerate(lines) if "run_file_allow" in l), None)
if route_i is None:
    print("[ERR] cannot find route line")
    sys.exit(2)

# find next def after route line
def_i = None
for i in range(route_i, min(route_i+200, len(lines))):
    if re.match(r"^\s*def\s+\w+\s*\(", lines[i]):
        def_i = i
        break
if def_i is None:
    print("[ERR] cannot find handler def after route")
    sys.exit(2)

func_indent = re.match(r"^(\s*)def\s", lines[def_i]).group(1)
func_indent_len = len(func_indent)

# find end of function block
end_i = len(lines)
for j in range(def_i+1, len(lines)):
    lj = lines[j]
    if lj.strip() == "":
        continue
    ind = len(re.match(r"^(\s*)", lj).group(1))
    if ind <= func_indent_len and (re.match(r"^\s*def\s+\w+\s*\(", lj) or re.match(r"^\s*@", lj)):
        end_i = j
        break

seg = lines[def_i:end_i]

# detect variable name assigned from request.args.get("path")
pathvar = "path"
rx = re.compile(r"^\s*([a-zA-Z_]\w*)\s*=\s*request\.args\.get\(\s*['\"]path['\"]", re.M)
joined = "".join(seg)
m = rx.search(joined)
if m:
    pathvar = m.group(1)

# find first return-line that includes "not allowed"
ret_idx = None
for k,l in enumerate(seg):
    if "return" in l and ("not allowed" in l.lower()):
        ret_idx = k
        break

if ret_idx is None:
    # fallback: abort(403) or 403
    for k,l in enumerate(seg):
        if "abort(" in l and "403" in l:
            ret_idx = k
            break

if ret_idx is None:
    print("[WARN] cannot find not-allowed return/abort in handler; no patch applied")
    p.write_text(s, encoding="utf-8")
    sys.exit(0)

ret_line = seg[ret_idx]
ret_indent = re.match(r"^(\s*)", ret_line).group(1)

# inject: if not _dash_allow_exact(path): <return...>
new_lines = []
new_lines.append(f"{ret_indent}# {MARK_PATCH}\n")
new_lines.append(f"{ret_indent}if not _dash_allow_exact({pathvar}):\n")
new_lines.append(ret_indent + "    " + ret_line.lstrip())

seg[ret_idx:ret_idx+1] = new_lines

# write back
lines[def_i:end_i] = seg
s2 = "".join(lines)
p.write_text(s2, encoding="utf-8")
print(f"[OK] patched handler: pathvar={pathvar}, at line~{def_i+1}")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
