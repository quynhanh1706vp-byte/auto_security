#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
RID="${RID:-VSP_CI_RUN_20251219_092640}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

echo "== [0] locate candidate python files containing run_file_allow =="
python3 - <<'PY'
from pathlib import Path
root = Path(".")
cands = []
for p in root.rglob("*.py"):
    s = str(p)
    if any(x in s for x in ("/out_ci/", "/out/", "/bin/", ".bak_", "__pycache__")):
        continue
    try:
        t = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "run_file_allow" in t or "/api/vsp/run_file_allow" in t:
        cands.append(p)
print("[CANDS]", len(cands))
for p in cands[:60]:
    print(" -", p)
PY

echo "== [1] patch the real handler by matching route/decorator or add_url_rule patterns =="
python3 - <<'PY'
from pathlib import Path
import re, time

MARK = "VSP_P0_ALIAS_REPORTS_GATE_V3"
need_alias = {
  "reports/run_gate_summary.json": "run_gate_summary.json",
  "reports/run_gate.json": "run_gate.json",
}

def patch_file(p: Path) -> bool:
    s = p.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return False

    # find occurrences of run_file_allow as route string
    hits = []
    for m in re.finditer(r"run_file_allow", s):
        hits.append(m.start())
    if not hits:
        return False

    # backup
    ts = time.strftime("%Y%m%d_%H%M%S")
    bak = p.with_name(p.name + f".bak_alias_v3_{ts}")
    bak.write_text(s, encoding="utf-8")

    lines = s.splitlines(True)

    # helper: find next def after line index
    def find_next_def(i0: int):
        for i in range(i0, min(len(lines), i0+200)):
            if re.match(r"^\s*def\s+\w+\s*\(", lines[i]):
                return i
        return None

    # helper: get block from def line to next top-level def (col 0)
    def extract_def_block(i_def: int):
        # detect indent of def line
        ind = re.match(r"^(\s*)", lines[i_def]).group(1)
        # end at next line starting with same indent + 'def ' (or end of file)
        for j in range(i_def+1, len(lines)):
            if re.match(rf"^{re.escape(ind)}def\s+\w+\s*\(", lines[j]):
                return (i_def, j)
        return (i_def, len(lines))

    # strategy A: decorator style: @app.route(...run_file_allow...) then def ...
    for i, ln in enumerate(lines):
        if "run_file_allow" not in ln:
            continue
        if "@app" in ln or "route(" in ln or "get(" in ln or "post(" in ln:
            i_def = find_next_def(i)
            if i_def is None:
                continue
            a,b = extract_def_block(i_def)
            block = lines[a:b]

            # locate where 'path' is read inside this function
            path_line = None
            lhs = None
            pats = [
                re.compile(r"^\s*(\w+)\s*=\s*.*\bget\b\s*\(.*['\"]path['\"]"),
                re.compile(r"^\s*(\w+)\s*=\s*.*request\.(args|values|form|json)\b.*['\"]path['\"]"),
            ]
            for k, bl in enumerate(block):
                for pat in pats:
                    m = pat.search(bl)
                    if m:
                        path_line = k
                        lhs = m.group(1)
                        break
                if path_line is not None:
                    break

            if path_line is None:
                # fallback: any assignment containing 'path'
                for k, bl in enumerate(block):
                    if "path" in bl and "=" in bl:
                        m = re.match(r"^\s*(\w+)\s*=", bl)
                        if m:
                            path_line = k
                            lhs = m.group(1)
                            break

            if path_line is None or not lhs:
                continue

            indent = re.match(r"^(\s*)", block[path_line]).group(1)
            inj = []
            inj.append(f"{indent}# ===================== {MARK} =====================\n")
            inj.append(f"{indent}# Alias reports/run_gate*.json -> root (commercial: avoid 403 spam)\n")
            inj.append(f"{indent}try:\n")
            inj.append(f"{indent}  _p0 = ({lhs} or \"\").replace(\"\\\\\\\\\",\"/\").lstrip(\"/\")\n")
            inj.append(f"{indent}  if _p0 in (\"reports/run_gate_summary.json\",\"reports/run_gate.json\"):\n")
            inj.append(f"{indent}    {lhs} = _p0.split(\"/\", 1)[1]\n")
            inj.append(f"{indent}except Exception:\n")
            inj.append(f"{indent}  pass\n")
            inj.append(f"{indent}# ===================== /{MARK} =====================\n")

            new_block = block[:path_line+1] + inj + block[path_line+1:]
            lines[a:b] = new_block
            p.write_text("".join(lines), encoding="utf-8")
            print(f"[OK] patched decorator handler in {p} (var={lhs})")
            return True

    # strategy B: add_url_rule("/api/vsp/run_file_allow", ..., view_func=xxx)
    m = re.search(r"add_url_rule\([^)]*run_file_allow[^)]*\)", s)
    if m:
        # try to find view_func=NAME
        m2 = re.search(r"view_func\s*=\s*(\w+)", s[m.start():m.end()])
        if m2:
            fn = m2.group(1)
            # find def fn(
            mdef = re.search(rf"(?m)^\s*def\s+{re.escape(fn)}\s*\(", s)
            if mdef:
                # locate the def line index
                def_line_idx = s[:mdef.start()].count("\n")
                a,b = extract_def_block(def_line_idx)
                block = lines[a:b]
                # same injection search
                path_line = None
                lhs = None
                pats = [
                    re.compile(r"^\s*(\w+)\s*=\s*.*\bget\b\s*\(.*['\"]path['\"]"),
                    re.compile(r"^\s*(\w+)\s*=\s*.*request\.(args|values|form|json)\b.*['\"]path['\"]"),
                ]
                for k, bl in enumerate(block):
                    for pat in pats:
                        mm = pat.search(bl)
                        if mm:
                            path_line = k
                            lhs = mm.group(1)
                            break
                    if path_line is not None:
                        break
                if path_line is None or not lhs:
                    return False
                indent = re.match(r"^(\s*)", block[path_line]).group(1)
                inj = [
                    f"{indent}# ===================== {MARK} =====================\n",
                    f"{indent}try:\n",
                    f"{indent}  _p0 = ({lhs} or \"\").replace(\"\\\\\\\\\",\"/\").lstrip(\"/\")\n",
                    f"{indent}  if _p0 in (\"reports/run_gate_summary.json\",\"reports/run_gate.json\"):\n",
                    f"{indent}    {lhs} = _p0.split(\"/\", 1)[1]\n",
                    f"{indent}except Exception:\n",
                    f"{indent}  pass\n",
                    f"{indent}# ===================== /{MARK} =====================\n",
                ]
                new_block = block[:path_line+1] + inj + block[path_line+1:]
                lines[a:b] = new_block
                p.write_text("".join(lines), encoding="utf-8")
                print(f"[OK] patched add_url_rule handler in {p} (fn={fn}, var={lhs})")
                return True

    # no patch applied; restore original (keep bak already created, but keep current unchanged)
    p.write_text(s, encoding="utf-8")
    return False

# run across candidates
root = Path(".")
cands = []
for f in root.rglob("*.py"):
    sf = str(f)
    if any(x in sf for x in ("/out_ci/", "/out/", "/bin/", ".bak_", "__pycache__")):
        continue
    try:
        t = f.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "run_file_allow" in t or "/api/vsp/run_file_allow" in t:
        cands.append(f)

patched = False
for f in cands:
    try:
        if patch_file(f):
            patched = True
            break
    except Exception as e:
        # ignore and continue scanning others
        continue

if not patched:
    raise SystemExit("[ERR] could not auto-patch: cannot resolve handler+path assignment")
PY

echo "== [2] compile check (main gateway + likely app modules) =="
python3 -m py_compile wsgi_vsp_ui_gateway.py 2>/dev/null || true
python3 -m py_compile vsp_demo_app.py 2>/dev/null || true

echo "== [3] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.7

echo "== [4] verify =="
echo "-- reports/run_gate_summary.json (expect 200) --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | sed -n '1,15p'
echo
echo "-- reports/run_gate.json (expect 200) --"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate.json" | sed -n '1,15p'
