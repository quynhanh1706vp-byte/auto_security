#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pick="$(grep -Rsl --include='*.py' -E '^\s*def\s+run_status_v1\s*\(' "$UI_ROOT" | head -n 1 || true)"
[ -n "${pick:-}" ] || { echo "[ERR] cannot find file with 'def run_status_v1(' under $UI_ROOT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "$pick.bak_persist_uireq_status_v13_${TS}"
echo "[BACKUP] $pick.bak_persist_uireq_status_v13_${TS}"

python3 - "$pick" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_FROM_STATUS_V13" in txt:
    print("[OK] already patched V13.")
    raise SystemExit(0)

helper = r'''
# === VSP_UIREQ_PERSIST_FROM_STATUS_V13 ===
from pathlib import Path as _Path
import json as _json
import time as _time
import os as _os

def _uireq_ui_root_v13():
    # usually ui/run_api/*.py -> parents[1] == ui/
    return _Path(__file__).resolve().parents[1]

def _uireq_state_dir_v13():
    d = _uireq_ui_root_v13() / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_safe_dict_v13(x):
    return x if isinstance(x, dict) else {}

def _uireq_state_update_v13(req_id: str, patch: dict):
    try:
        fp = _uireq_state_dir_v13() / f"{req_id}.json"
        try:
            cur = _json.loads(fp.read_text(encoding="utf-8"))
        except Exception:
            cur = {"ok": True, "req_id": req_id}

        patch = _uireq_safe_dict_v13(patch)
        for k, v in patch.items():
            if v is None:
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or req_id
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = str(fp) + ".tmp"
        _Path(tmp).write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        _os.replace(tmp, fp)
        return True
    except Exception:
        try:
            app.logger.exception("[UIREQ][V13] persist update failed")
        except Exception:
            pass
        return False
# === END VSP_UIREQ_PERSIST_FROM_STATUS_V13 ===
'''.lstrip("\n")

# insert helper after imports (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + helper + "\n" + txt[m.end():]
else:
    lines0 = txt.splitlines(True)
    txt = "".join(lines0[:1]) + "\n" + helper + "\n" + "".join(lines0[1:])

# locate run_status_v1 block
mm = re.search(r'^\s*def\s+run_status_v1\s*\((?P<args>[^\)]*)\)\s*:\s*$', txt, flags=re.M)
if not mm:
    print("[ERR] cannot find def run_status_v1(...)")
    raise SystemExit(3)

args = mm.group("args").strip()
# pick first param name (exclude self)
first_param = None
if args:
    first_param = args.split(",")[0].strip().split("=")[0].strip()
    if first_param == "self" and "," in args:
        first_param = args.split(",")[1].strip().split("=")[0].strip()

def_start = mm.start()
def_indent = len(mm.group(0)) - len(mm.group(0).lstrip(" \t"))

lines = txt.splitlines(True)

# map char offset -> line index
pos = 0
li_def = 0
for i, ln in enumerate(lines):
    if pos <= def_start < pos + len(ln):
        li_def = i
        break
    pos += len(ln)

# find end of function
end = len(lines)
for j in range(li_def + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = j
        break

# helper: parse "return jsonify(" ... ")" possibly multiline, keep possible tail like ", 200"
def parse_jsonify_return(start_line_idx):
    # returns (block_lines, consumed_lines)
    s = "".join(lines[start_line_idx:end])
    m = re.search(r'^\s*return\s+jsonify\s*\(', s, flags=re.M)
    if not m:
        return None
    # compute absolute offset from start_line_idx
    abs0 = m.start()
    # find the '(' position
    paren_i = s.find("(", m.end()-1)
    if paren_i == -1:
        return None
    i = paren_i + 1
    depth = 1
    in_str = None
    esc = False
    while i < len(s):
        ch = s[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
        else:
            if ch in ("'", '"'):
                in_str = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    break
        i += 1
    if depth != 0:
        return None

    inside = s[paren_i+1:i].strip()
    tail = s[i+1:]
    # tail may start with ", 200" on same line; we only keep up to newline
    tail_line = tail.splitlines(True)[0]
    # compute how many lines consumed up to end of this return statement line
    consumed = (s[:i+1].count("\n")) + 1  # at least current line
    # find indent of return line
    ret_line = s[m.start():].splitlines(True)[0]
    indent = re.match(r'^(\s*)', ret_line).group(1)

    rid_expr = first_param or "req_id"
    hook = f"""{indent}# === VSP_UIREQ_PERSIST_FROM_STATUS_V13 hook ===
{indent}resp = {inside}
{indent}try:
{indent}    _rid = locals().get("{rid_expr}") or locals().get("req_id") or locals().get("request_id") or (resp.get("req_id") if isinstance(resp, dict) else None)
{indent}    if _rid:
{indent}        _uireq_state_update_v13(_rid, _uireq_safe_dict_v13(resp))
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_UIREQ_PERSIST_FROM_STATUS_V13 hook ===
{indent}return jsonify(resp){tail_line.strip()}
"""
    return hook.splitlines(True), consumed

# rewrite all return jsonify(...) inside run_status_v1
out = []
i = 0
while i < len(lines):
    if li_def <= i < end and re.match(r'^\s*return\s+jsonify\s*\(', lines[i]):
        parsed = parse_jsonify_return(i)
        if parsed is None:
            out.append(lines[i])
            i += 1
            continue
        block_lines, consumed = parsed
        out.extend(block_lines)
        i += consumed
        continue
    out.append(lines[i])
    i += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] patched {p.name} (V13): rewrote all return jsonify(...) in run_status_v1 to persist payload.")
PY

echo "== PY COMPILE CHECK =="
python3 -m py_compile "$pick" && echo "[OK] py_compile passed"

echo "== QUICK GREP (V13) =="
grep -n "VSP_UIREQ_PERSIST_FROM_STATUS_V13" "$pick" | head -n 120 || true

echo "[DONE] Restart 8910 then call run_status_v1 a few times; state file will update when ci_run_dir becomes available."
