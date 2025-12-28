#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

systemctl --user stop vsp-ui-8910.service 2>/dev/null || true
sleep 1

echo "== [1] pick best backup for run_api/vsp_run_api_v1.py =="
best=""
for b in $(ls -1t run_api/vsp_run_api_v1.py.bak_* 2>/dev/null || true); do
  python3 -m py_compile "$b" >/dev/null 2>&1 || continue

  # heuristic: must contain def run_v1 and look like real spawn logic (subprocess / Popen / CI)
  if ! grep -qE '^\s*def\s+run_v1\s*\(' "$b"; then
    continue
  fi
  if grep -qiE 'RUN_V1_DEFAULTS_V9_CACHEJSON|RUN_V1_RETURNED_NONE|VSP_RUNV1_V(14|15|16)' "$b" 2>/dev/null; then
    continue
  fi
  if ! grep -qiE 'subprocess|Popen|run_all_tools|VSP_CI|ci_gate|spawn' "$b" 2>/dev/null; then
    # allow backup even if heuristic misses; but prefer ones with spawn keywords
    :
  fi

  # avoid "cụt" (run_v1 body too short)
  nlines="$(python3 - <<PY
import re
from pathlib import Path
t=Path("$b").read_text(encoding="utf-8", errors="ignore")
m=re.search(r"(?m)^(\\s*)def\\s+run_v1\\s*\\(\\s*\\)\\s*:", t)
if not m:
  print(0); raise SystemExit
ind=m.group(1)
start=m.start()
# find next top-level def (same indent)
m2=re.search(rf"(?m)^{{re.escape(ind)}}def\\s+\\w+\\s*\\(", t[m.end():])
end=(m.end()+m2.start()) if m2 else len(t)
blk=t[start:end].splitlines()
print(len(blk))
PY
)"
  if [ "${nlines:-0}" -lt 40 ]; then
    continue
  fi

  best="$b"
  break
done

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_pre_v17_${TS}"
echo "[BACKUP] $F.bak_pre_v17_${TS}"

if [ -n "$best" ]; then
  echo "[OK] restore from: $best"
  cp -f "$best" "$F"
else
  echo "[WARN] no suitable backup found; will patch current file anyway (may keep returning 500)."
fi

echo "== [2] patch run_v1 defaults + guaranteed return (commercial) =="

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG1 = "# === VSP_RUN_V1_COMMERCIAL_DEFAULTS_V17 ==="
TAG2 = "# === VSP_RUN_V1_COMMERCIAL_FALLBACK_RETURN_V17 ==="
if TAG1 in t and TAG2 in t:
    print("[OK] already patched")
    raise SystemExit(0)

# ensure imports exist (safe)
if not re.search(r"(?m)^\s*import\s+os\s*$", t): t = "import os\n" + t
if not re.search(r"(?m)^\s*import\s+json\s*$", t): t = "import json\n" + t

m = re.search(r"(?m)^(?P<ind>\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", t)
if not m:
    raise SystemExit("[ERR] cannot find def run_v1() in run_api/vsp_run_api_v1.py")

ind_def = m.group("ind")
# find indent used for body (from next meaningful line)
lines = t.splitlines(True)
start_idx = t[:m.end()].count("\n")
body_indent = None
for j in range(start_idx, min(len(lines), start_idx+50)):
    s = lines[j]
    if s.strip() == "" or s.lstrip().startswith("#"):
        continue
    m2 = re.match(r"^(\s+)\S", s)
    if m2:
        body_indent = m2.group(1)
        break
if body_indent is None:
    body_indent = ind_def + "  "  # project style often 2 spaces

# insert defaults block early in function (right after first data=get_json if present)
# choose anchor within first 25 lines of run_v1 block
run_start = start_idx
# find end of function by next def at same indent (or EOF)
text_after = "".join(lines[run_start+1:])
mnext = re.search(rf"(?m)^{re.escape(ind_def)}def\s+\w+\s*\(", text_after)
run_end = (run_start+1 + text_after[:mnext.start()].count("\n")) if mnext else len(lines)

blk = lines[run_start:run_end]
head = "".join(blk[: min(len(blk), 30)])

ins_pos = None
# prefer after "data = request.get_json"
for k in range(0, min(len(blk), 30)):
    if re.search(r"\brequest\.get_json\(", blk[k]):
        ins_pos = k+1
        break
if ins_pos is None:
    ins_pos = 1  # after def line

defaults = (
    f"{body_indent}{TAG1}\n"
    f"{body_indent}# Commercial: accept empty payload by applying safe defaults (and freeze request JSON cache)\n"
    f"{body_indent}try:\n"
    f"{body_indent}    data = data if isinstance(data, dict) else {{}}\n"
    f"{body_indent}except Exception:\n"
    f"{body_indent}    data = {{}}\n"
    f"{body_indent}if not isinstance(data, dict):\n"
    f"{body_indent}    data = {{}}\n"
    f"{body_indent}data.setdefault('mode','local')\n"
    f"{body_indent}data.setdefault('profile','FULL_EXT')\n"
    f"{body_indent}data.setdefault('target_type','path')\n"
    f"{body_indent}data.setdefault('target','/home/test/Data/SECURITY-10-10-v4')\n"
    f"{body_indent}# env_overrides must be dict\n"
    f"{body_indent}if 'env_overrides' in data and not isinstance(data.get('env_overrides'), dict):\n"
    f"{body_indent}    data.pop('env_overrides', None)\n"
    f"{body_indent}# IMPORTANT: subsequent request.get_json()/request.json must see the same defaults\n"
    f"{body_indent}try:\n"
    f"{body_indent}    request._cached_json = {{False: data, True: data}}\n"
    f"{body_indent}except Exception:\n"
    f"{body_indent}    pass\n"
)

# remove old broken defaults tags if any (safe)
t2 = "".join(lines[:run_start]) + "".join(blk) + "".join(lines[run_end:])
t2 = re.sub(r"(?ms)^\s*# === VSP_RUN_V1_DEFAULTS_.*?^\s*# === END VSP_RUN_V1_DEFAULTS_.*?$", "", t2)

# rebuild blk after cleanup
lines2 = t2.splitlines(True)
t2 = "".join(lines2)
m = re.search(r"(?m)^(?P<ind>\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", t2)
start_idx = t2[:m.end()].count("\n")
ind_def = m.group("ind")
# recompute end
lines2 = t2.splitlines(True)
text_after = "".join(lines2[start_idx+1:])
mnext = re.search(rf"(?m)^{re.escape(ind_def)}def\s+\w+\s*\(", text_after)
run_end = (start_idx+1 + text_after[:mnext.start()].count("\n")) if mnext else len(lines2)
blk = lines2[start_idx:run_end]

# idempotent insert defaults
if TAG1 not in "".join(blk):
    # recompute ins_pos again quickly
    ins_pos = None
    for k in range(0, min(len(blk), 30)):
        if re.search(r"\brequest\.get_json\(", blk[k]):
            ins_pos = k+1
            break
    if ins_pos is None:
        ins_pos = 1
    blk = blk[:ins_pos] + [defaults] + blk[ins_pos:]

# ensure there is a safe fallback return at end if function falls through
func_txt = "".join(blk)
if TAG2 not in func_txt:
    fallback = (
        f"\n{body_indent}{TAG2}\n"
        f"{body_indent}# Commercial: never fall through without returning a Flask response\n"
        f"{body_indent}try:\n"
        f"{body_indent}    from flask import jsonify as _jsonify\n"
        f"{body_indent}    return _jsonify({{'ok': False, 'error': 'RUN_V1_MISSING_RETURN', 'http_code': 500}}), 500\n"
        f"{body_indent}except Exception:\n"
        f"{body_indent}    return {{'ok': False, 'error': 'RUN_V1_MISSING_RETURN', 'http_code': 500}}, 500\n"
    )
    blk.append(fallback)

out = "".join(lines2[:start_idx]) + "".join(blk) + "".join(lines2[run_end:])
p.write_text(out, encoding="utf-8")
print("[OK] patched run_v1 defaults + fallback return V17")
PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"

echo "== [3] hard free port 8910 then start service =="
PORT=8910
PIDS="$(ss -ltnp | awk -v p=":$PORT" '$4 ~ p {print $0}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u)"
for pid in $PIDS; do echo "[KILL] $pid"; kill -9 "$pid" 2>/dev/null || true; done
sleep 1

systemctl --user start vsp-ui-8910.service
sleep 1

echo "== verify healthz =="
curl -sS -i http://127.0.0.1:8910/healthz | sed -n '1,60p'
echo
echo "== verify run_v1 {} =="
curl -sS -i -X POST http://127.0.0.1:8910/api/vsp/run_v1 -H 'Content-Type: application/json' -d '{}' | sed -n '1,220p'
