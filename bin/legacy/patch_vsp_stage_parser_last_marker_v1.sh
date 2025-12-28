#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_stage_last_${TS}"
echo "[BACKUP] $F.bak_stage_last_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Replace whole function def _extract_stage_from_tail(...) block
rx = re.compile(r"^def\s+_extract_stage_from_tail\s*\(.*?\)\s*:\s*$", re.M)
m = rx.search(txt)
if not m:
    print("[ERR] cannot find def _extract_stage_from_tail")
    raise SystemExit(2)

start = m.start()
after = txt[m.end():]
m2 = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
end = m.end() + (m2.start() if m2 else len(after))

new_fn = r'''
def _extract_stage_from_tail(tail_text: str):
  """
  Commercial contract:
  - Parse stage marker from log tail using LAST-MARKER-WINS (scan from end).
  - Support pattern: "===== [3/8] KICS (EXT) ====="
  - stage_index is 0..n-1 (idx-1), progress is 0..100 based on idx/total.
  """
  import re

  if not tail_text:
    return {}

  pat = re.compile(r"^\s*=+\s*\[(\d+)\s*/\s*(\d+)\]\s*(.*?)\s*=+\s*$")

  for raw in reversed((tail_text or "").splitlines()):
    line = (raw or "").strip()
    m = pat.match(line)
    if not m:
      continue

    try:
      idx = int(m.group(1))
      total = int(m.group(2))
      name = (m.group(3) or "").strip()
    except Exception:
      continue

    if total <= 0:
      total = 0
    if idx < 0:
      idx = 0

    # stage_index: 0..n-1
    stage_index = max(idx - 1, 0) if total else 0

    # progress: idx/total -> 0..100
    if total > 0:
      pct = int(round((max(min(idx, total), 0) / total) * 100))
    else:
      pct = 0

    if pct < 0: pct = 0
    if pct > 100: pct = 100

    return {"i": stage_index, "total": total, "name": name, "progress": pct}

  return {}
'''.lstrip("\n")

txt2 = txt[:start] + new_fn + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced _extract_stage_from_tail with LAST-MARKER-WINS parser")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== Smoke unit test for parser (no server needed) =="
python3 - <<'PY'
from run_api.vsp_run_api_v1 import _extract_stage_from_tail

tail = """
some old stuff
===== [1/8] GITLEAKS =====
blah blah
===== [3/8] KICS (EXT) =====
more lines
"""
print(_extract_stage_from_tail(tail))
PY

echo "== Restart 8910 (fallback default-OFF already) =="
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Quick check: status endpoint still OK =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
print({k: obj.get(k) for k in ["ok","status","error","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]})
PY

echo "[DONE]"
