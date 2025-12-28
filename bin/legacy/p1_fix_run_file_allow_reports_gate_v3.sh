#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== locate handler source for /api/vsp/run_file_allow =="
PYF="$(python3 - <<'PY'
import inspect, sys
import vsp_demo_app

app = getattr(vsp_demo_app, "app", None)
if app is None and hasattr(vsp_demo_app, "create_app"):
    app = vsp_demo_app.create_app()
if app is None:
    print("")
    sys.exit(0)

target_rule = None
target_ep = None
for r in app.url_map.iter_rules():
    if r.rule == "/api/vsp/run_file_allow":
        target_rule = r.rule
        target_ep = r.endpoint
        break

if not target_ep:
    # fallback: contains substring
    for r in app.url_map.iter_rules():
        if "run_file_allow" in r.rule:
            target_rule = r.rule
            target_ep = r.endpoint
            break

if not target_ep:
    print("")
    sys.exit(0)

fn = app.view_functions.get(target_ep)
print(inspect.getsourcefile(fn) or "")
PY
)"

if [ -z "$PYF" ]; then
  echo "[ERR] cannot locate python source for /api/vsp/run_file_allow via flask introspection"
  echo "Tip: ensure vsp_demo_app.py is the running app and imports correctly."
  exit 2
fi
if [ ! -f "$PYF" ]; then
  echo "[ERR] resolved source not found on disk: $PYF"
  exit 2
fi

echo "[OK] handler source: $PYF"
cp -f "$PYF" "${PYF}.bak_gate_reports_v3_${TS}"
echo "[BACKUP] ${PYF}.bak_gate_reports_v3_${TS}"

python3 - "$PYF" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_REPORTS_GATE_V3"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert allow-override + strict gate path set inside run_file_allow()
m = re.search(r'(?ms)^\s*def\s+run_file_allow\s*\(.*?\)\s*:\s*\n', s)
if not m:
    raise SystemExit("[ERR] cannot find def run_file_allow(...) in " + str(p))

# find indentation level inside function (next line)
after = s[m.end():]
m2 = re.search(r'(?m)^([ \t]+)\S', after)
indent = m2.group(1) if m2 else "    "

inject = f"""\n{indent}# {marker}\n{indent}GATE_REPORTS_ALLOW = {{\n{indent}    "reports/run_gate_summary.json",\n{indent}    "reports/run_gate.json",\n{indent}    "run_gate_summary.json",\n{indent}    "run_gate.json",\n{indent}}}\n"""

# Try to inject after `path = request.args.get("path"...`
ins_pos = None
for pat in [
    r'(?m)^\s*path\s*=\s*request\.(args|values)\.get\(\s*[\'"]path[\'"]',
    r'(?m)^\s*path\s*=\s*\w+\.get\(\s*[\'"]path[\'"]',
]:
    mm = re.search(pat, after)
    if mm:
        line_end = after.find("\n", mm.end())
        if line_end == -1:
            line_end = len(after)
        ins_pos = m.end() + line_end + 1
        break

if ins_pos is None:
    # fallback: insert immediately after function header
    ins_pos = m.end()

s = s[:ins_pos] + inject + s[ins_pos:]

# Now relax allow-check: common patterns
repls = 0

# Pattern A: if path not in ALLOW: return 403
patA = re.compile(r'(?m)^(?P<i>\s*)if\s+(?P<var>path)\s+not\s+in\s+(?P<allow>\w+)\s*:\s*$')
def replA(m):
    nonlocal repls
    repls += 1
    i=m.group("i"); var=m.group("var"); allow=m.group("allow")
    return f'{i}if ({var} not in {allow}) and ({var} not in GATE_REPORTS_ALLOW):'
s, nA = patA.subn(replA, s, count=1)

# Pattern B: if not is_allowed(path): return 403  (add fast-path before it)
if nA == 0:
    patB = re.compile(r'(?m)^(?P<i>\s*)if\s+not\s+(?P<fn>is_allowed|allowed)\(\s*path\s*\)\s*:\s*$')
    mB = patB.search(s)
    if mB:
        i=mB.group("i")
        fast = f'{i}if path in GATE_REPORTS_ALLOW:\n{i}    pass\n{i}else:\n'
        # indent original if-block by 2 spaces
        start = mB.start()
        # find block until next non-indented line
        lines = s[start:].splitlines(True)
        out=[]
        out.append(fast)
        for ln in lines:
            if ln.startswith(i) and not ln.startswith(i+" "):
                # keep within same level; indent it
                out.append(i+"  "+ln)
            else:
                out.append(i+"  "+ln)
            # stop after first line only; we don't want to reindent whole file blindly
            break
        s = s[:start] + "".join(out) + s[start+len(lines[0]):]
        repls += 1

# Append marker footer
s += f"\n# {marker}\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
print("[OK] allow-check repls:", repls)
PY

echo "== py_compile =="
python3 -m py_compile "$PYF" && echo "[OK] py_compile OK"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.8

echo "== verify 403->200 for reports gate path =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1&offset=0" | python3 -c 'import sys,json; j=json.load(sys.stdin); it=(j.get("items") or [{}])[0]; print(it.get("run_id") or it.get("rid") or "")' 2>/dev/null || true)"
echo "[RID]=$RID"

for pth in "reports/run_gate_summary.json" "reports/run_gate.json"; do
  echo "-- $pth"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$pth" || true
  grep -iE 'HTTP/|Content-Type|X-VSP-Fallback-Path|Content-Disposition' /tmp/h | sed 's/\r$//'
  head -c 160 /tmp/b; echo; echo
done

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R)."
