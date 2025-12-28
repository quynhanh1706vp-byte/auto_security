#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] snapshot =="
cp -f "$W" "${W}.bak_truefix_v12_snapshot_${TS}"
echo "[BACKUP] ${W}.bak_truefix_v12_snapshot_${TS}"

echo "== [1] auto-restore to latest compiling candidate (current or backup) =="
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
cands = [w] + baks
for f in cands:
    try:
        py_compile.compile(str(f), doraise=True)
        print(str(f))
        break
    except Exception:
        continue
PY
)"
[ -n "$GOOD" ] || { echo "[ERR] no compiling backup found"; exit 2; }
echo "[OK] compiling candidate = $GOOD"
if [ "$GOOD" != "$W" ]; then
  cp -f "$GOOD" "$W"
  echo "[OK] restored $W from $GOOD"
fi

echo "== [2] patch handler vsp_run_file_allow (reports/ alias) without try =="
python3 - <<'PY'
import re
from pathlib import Path

MARK="VSP_P0_TRUEFIX_REPORTS_GATE_V12"

p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8",errors="replace").splitlines(True)
s="".join(lines)

# detect handler function from route
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
fn=m.group(1) if m else "vsp_run_file_allow_v5"

# locate def block
di=None
for i,l in enumerate(lines):
  if re.match(r'^\s*def\s+'+re.escape(fn)+r'\s*\(', l):
    di=i; break
if di is None:
  raise SystemExit(f"[ERR] cannot find def {fn}")

indent_def=len(lines[di]) - len(lines[di].lstrip(" "))
end=len(lines)
for j in range(di+1,len(lines)):
  lj=lines[j]
  if lj.strip()=="":
    continue
  if (len(lj)-len(lj.lstrip(" ")))==indent_def and (lj.lstrip().startswith("def ") or lj.lstrip().startswith("@")):
    end=j; break

blk=lines[di:end]

# find where path variable is read (best-effort) to insert helper right after it
ins_at=None
for k,l in enumerate(blk):
  if re.search(r'args\.get\(\s*[\'"]path[\'"]', l) or re.search(r'get\(\s*[\'"]path[\'"]', l) and "=" in l:
    ins_at=k+1
    break
# fallback: insert right after first assignment like X = ...
if ins_at is None:
  for k,l in enumerate(blk):
    if re.match(r'^\s*\w+\s*=\s*', l):
      ins_at=k+1
      break
if ins_at is None:
  ins_at=1

ins_indent=re.match(r'^(\s*)', blk[ins_at-1]).group(1)

helper = (
  f"{ins_indent}# --- {MARK} ---\\n"
  f"{ins_indent}def _vsp_allow_key(_p):\\n"
  f"{ins_indent}    if isinstance(_p, str) and _p.startswith('reports/'):\\n"
  f"{ins_indent}        _t = _p[len('reports/'):]\\n"
  f"{ins_indent}        if _t in ('run_gate_summary.json','run_gate.json'):\\n"
  f"{ins_indent}            return _t\\n"
  f"{ins_indent}    return _p\\n"
  f"{ins_indent}# --- /{MARK} ---\\n"
)

if any(MARK in x for x in blk):
  print("[OK] marker already present; continue rewrite only")
else:
  blk.insert(ins_at, helper)
  print(f"[OK] inserted helper into {fn} at local index {ins_at}")

# rewrite allow checks robustly (any var name)
rew=0
for i,l in enumerate(blk):
  t=l.strip()
  if not t or t.startswith("#"):
    continue
  # avoid touching JSON string literals etc.
  if ("'not allowed'" in l) or ('"not allowed"' in l):
    continue

  old=l

  # membership check: if X not in ALLOW:
  l=re.sub(r'(\bif\s+)([A-Za-z_][A-Za-z0-9_]*)(\s+not\s+in\s+ALLOW\b)',
           r'\1_vsp_allow_key(\2)\3', l)

  # allow.get(X
  l=re.sub(r'\bALLOW\.get\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*([,\)])',
           r'ALLOW.get(_vsp_allow_key(\1)\2', l)

  # ALLOW[X]
  l=re.sub(r'\bALLOW\[\s*([A-Za-z_][A-Za-z0-9_]*)\s*\]',
           r'ALLOW[_vsp_allow_key(\1)]', l)

  if l!=old:
    blk[i]=l
    rew+=1

lines[di:end]=blk
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched {fn}: rewrites={rew}")
PY

echo "== [3] compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== [4] restart =="
systemctl restart "$SVC" || true
sleep 1.0

echo "== [5] wait service =="
for i in 1 2 3 4 5; do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null; then echo "[OK] /api/vsp/runs up"; break; fi
  sleep 0.8
done

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

echo "== [6] sanity: run_file_allow reports/run_gate_summary.json (must NOT be 403 not-allowed) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80
