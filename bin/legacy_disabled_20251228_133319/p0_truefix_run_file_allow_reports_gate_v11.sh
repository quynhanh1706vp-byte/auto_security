#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_truefix_v11_${TS}"
echo "[BACKUP] ${W}.bak_truefix_v11_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

MARK="VSP_P0_TRUEFIX_REPORTS_GATE_V11"

p=Path("wsgi_vsp_ui_gateway.py")
lines=p.read_text(encoding="utf-8",errors="replace").splitlines(True)
s="".join(lines)

# detect handler fn from route
m=re.search(r'add_url_rule\(\s*["\']/api/vsp/run_file_allow["\']\s*,\s*["\'][^"\']+["\']\s*,\s*([A-Za-z_][A-Za-z0-9_]*)\s*,', s)
fn=m.group(1) if m else "vsp_run_file_allow_v5"

# locate def block
di=None
for i,l in enumerate(lines):
  if re.match(r'^\s*def\s+'+re.escape(fn)+r'\s*\(', l):
    di=i; break
if di is None:
  raise SystemExit(f"[ERR] cannot find def {fn}")

indent=len(lines[di]) - len(lines[di].lstrip(" "))
end=len(lines)
for j in range(di+1,len(lines)):
  lj=lines[j]
  if lj.strip()=="":
    continue
  if (len(lj)-len(lj.lstrip(" ")))==indent and (lj.lstrip().startswith("def ") or lj.lstrip().startswith("@")):
    end=j; break

blk=lines[di:end]

if any(MARK in x for x in blk):
  print(f"[OK] marker already present in {fn}, skip insert")
else:
  # find rel assignment (best-effort)
  rel_i=None
  for k,l in enumerate(blk):
    if re.match(r'^\s*rel\s*=\s*', l):
      rel_i=k; break
  if rel_i is None:
    # fallback: find line assigning from request.args.get("path")
    for k,l in enumerate(blk):
      if "args.get" in l and "path" in l and "=" in l:
        rel_i=k; break
  if rel_i is None:
    raise SystemExit(f"[ERR] cannot find rel assignment inside {fn}")

  ins_indent=re.match(r'^(\s*)', blk[rel_i]).group(1)
  inject = (
    f"{ins_indent}# --- {MARK} ---\\n"
    f"{ins_indent}_vsp_allow_key = rel\\n"
    f"{ins_indent}try:\\n"
    f"{ins_indent}    if isinstance(_vsp_allow_key, str) and _vsp_allow_key.startswith('reports/'):\\n"
    f"{ins_indent}        _s = _vsp_allow_key[len('reports/'):]\\n"
    f"{ins_indent}        if _s in ('run_gate_summary.json','run_gate.json'):\\n"
    f"{ins_indent}            _vsp_allow_key = _s\\n"
    f"{ins_indent}except Exception:\\n"
    f"{ins_indent}    _vsp_allow_key = rel\\n"
    f"{ins_indent}# --- /{MARK} ---\\n"
  )
  blk.insert(rel_i+1, inject)
  print(f"[OK] inserted normalize after rel= (fn={fn})")

# rewrite allow-check usages inside handler block
rew=0
for i,l in enumerate(blk):
  if "ALLOW" not in l:
    continue
  old=l
  l=l.replace("ALLOW.get(rel", "ALLOW.get(_vsp_allow_key")
  l=l.replace("ALLOW[rel", "ALLOW[_vsp_allow_key")
  l=re.sub(r'\bif\s+rel\s+not\s+in\s+ALLOW\b', 'if _vsp_allow_key not in ALLOW', l)
  l=re.sub(r'\bif\s+rel\s+not\s+in\s+ALLOW\.keys\(\)', 'if _vsp_allow_key not in ALLOW.keys()', l)
  if l!=old:
    blk[i]=l
    rew+=1

lines[di:end]=blk
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched {fn}: rewrites={rew}")
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.9

echo "== wait /api/vsp/runs =="
for i in 1 2 3 4 5; do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null; then echo "[OK] up"; break; fi
  sleep 0.7
done

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

echo "== sanity: run_file_allow for reports/run_gate_summary.json (must NOT be 403 not-allowed) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80
