#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need cp; need systemctl; need curl; need ss; need tail

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] snapshot current (may be broken) =="
cp -f "$W" "${W}.bak_v8_snapshot_${TS}"
echo "[SNAPSHOT] ${W}.bak_v8_snapshot_${TS}"

echo "== [1] find latest compiling backup =="
GOOD=""
python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)

good = None
for b in baks[:300]:  # scan newest first
    try:
        py_compile.compile(str(b), doraise=True)
        good = str(b)
        break
    except Exception:
        continue

print(good or "")
PY
GOOD="$(python3 - <<'PY'
from pathlib import Path
import py_compile
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda x: x.stat().st_mtime, reverse=True)
for b in baks[:300]:
    try:
        py_compile.compile(str(b), doraise=True)
        print(b)
        break
    except Exception:
        pass
PY
)"

if [ -z "${GOOD:-}" ]; then
  echo "[ERR] cannot find any compiling backup. We'll try to auto-comment marker lines in-place."
else
  cp -f "$GOOD" "$W"
  echo "[OK] restored from compiling backup: $GOOD"
fi

echo "== [2] patch: comment stray marker lines that can break Python =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace").splitlines(True)

out=[]
changed=0
for line in s:
    raw=line.rstrip("\n")
    # Lines like:  VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C =====================
    # or:         ===================== /VSP_... =====================
    if (("VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C" in raw) or
        re.search(r"=+\s*VSP_[A-Z0-9_\/\-]+\s*=+", raw) or
        re.search(r"^\s*=+\s*/?VSP_[A-Z0-9_\/\-]+\s*=+\s*$", raw) or
        re.search(r"^\s*=+\s*$", raw)):
        if not raw.lstrip().startswith("#"):
            out.append("# " + raw + "\n")
            changed += 1
            continue
    out.append(line)

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] commented marker lines: {changed}")
PY

echo "== [3] patch: add reports/run_gate_summary.json into ALLOW blocks (set/list) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

need = ["reports/run_gate_summary.json", "reports/run_gate.json"]

# Capture ALLOW = { ... } or ALLOW = [ ... ] blocks (multiline)
pat = re.compile(r'(?ms)^(\s*)ALLOW\s*=\s*(\{.*?\}|\[.*?\])\s*$', re.M)

def ensure_items(block:str)->tuple[str,int]:
    # only patch blocks that already include run_gate_summary.json (the base allowlist)
    if "run_gate_summary.json" not in block:
        return block, 0
    addn=0
    # detect quote style
    q = '"' if ('"run_gate_summary.json"' in block or '"run_gate.json"' in block) else "'"
    for item in need:
        if item in block:
            continue
        # insert after run_gate_summary.json if possible
        ins = f'{q}{item}{q},'
        block2, n = re.subn(
            rf'({re.escape(q)}run_gate_summary\.json{re.escape(q)}\s*,\s*)',
            r'\1' + "        " + ins + "\n",
            block,
            count=1
        )
        if n == 0:
            # fallback: insert before closing brace/bracket
            block2 = re.sub(r'(\n\s*[}\]])', f'\n        {ins}\n\\1', block, count=1)
        if block2 != block:
            block = block2
            addn += 1
    return block, addn

changed_blocks=0
added_total=0

def repl(m: re.Match)->str:
    global changed_blocks, added_total
    indent = m.group(1)
    whole = m.group(0)
    rhs = m.group(2)
    new_rhs, addn = ensure_items(rhs)
    if new_rhs != rhs:
        changed_blocks += 1
        added_total += addn
        return f"{indent}ALLOW = {new_rhs}"
    return whole

s2 = pat.sub(repl, s)
p.write_text(s2, encoding="utf-8")
print(f"[OK] ALLOW blocks changed={changed_blocks} added_items={added_total}")
PY

echo "== [4] compile check =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [5] restart service =="
systemctl restart "$SVC" || true
sleep 1.0

echo "== [6] sanity port/listener =="
ss -ltnp | egrep '(:8910)\b' || { echo "[ERR] 8910 not listening"; systemctl status "$SVC" --no-pager || true; exit 3; }

echo "== [7] sanity endpoints =="
curl -fsS -I "$BASE/" | head -n 5 || true
curl -fsS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo

RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])')"
echo "[RID]=$RID"

echo "== [8] run_file_allow (expect NOT 403 not allowed) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
echo "[DONE] Hard reload /runs (Ctrl+Shift+R)."
