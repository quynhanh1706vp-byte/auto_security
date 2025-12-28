#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

echo "== Patch WSGI preempt: add gitleaks summary injection =="

python3 - <<'PY'
from pathlib import Path
import re, sys, time

ROOT = Path("/home/test/Data/SECURITY_BUNDLE/ui")
cands = list(ROOT.rglob("*.py"))

# 1) Find preempt implementation file
hits = []
for f in cands:
    try:
        s = f.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        continue
    if "VSP_WSGI_PREEMPT_V1" in s or "wsgi_preempt" in s.lower():
        hits.append((f, s))

if not hits:
    print("[ERR] cannot locate WSGI preempt file (no VSP_WSGI_PREEMPT_V1 / wsgi_preempt found)")
    raise SystemExit(2)

# Prefer file that mentions run_status_v2 as well
def score(s: str) -> int:
    sc = 0
    if "run_status_v2" in s: sc += 5
    if "FINAL" in s: sc += 1
    if "ci_run_dir" in s: sc += 1
    if "kics_summary.json" in s or "semgrep_summary.json" in s or "trivy_summary.json" in s: sc += 3
    return sc

hits.sort(key=lambda x: score(x[1]), reverse=True)
target, txt = hits[0]
print(f"[OK] target_preempt_file={target}")

TAG = "# === VSP_WSGI_PREEMPT_ADD_GITLEAKS_V1 ==="
if TAG in txt:
    print("[OK] tag exists, skip")
    raise SystemExit(0)

# 2) Find an anchor line in preempt builder where other tool summaries are injected
anchor_pats = [
    r"trivy_summary\.json",
    r"semgrep_summary\.json",
    r"kics_summary\.json",
    r"status\[['\"]trivy_verdict['\"]\]",
    r"status\[['\"]semgrep_verdict['\"]\]",
    r"status\[['\"]kics_verdict['\"]\]",
    r"has_trivy",
    r"has_semgrep",
    r"has_kics",
]
anchors = []
for pat in anchor_pats:
    for m in re.finditer(rf"(?m)^(?P<ind>\s*).*(?:{pat}).*$", txt):
        anchors.append(m)
if not anchors:
    print("[ERR] cannot find any anchor (kics/semgrep/trivy) inside preempt file; abort to avoid wrong insert")
    raise SystemExit(3)

# Use the LAST anchor to insert after it (safe: after existing tool injections)
m = anchors[-1]
ind = m.group("ind")
line_end = txt.find("\n", m.end())
if line_end == -1:
    line_end = m.end()

inject = "\n".join([
    f"{ind}{TAG}",
    f"{ind}try:",
    f"{ind}  import os, json",
    f"{ind}  _gl_paths = [",
    f"{ind}    os.path.join(ci_run_dir,'gitleaks','gitleaks_summary.json'),",
    f"{ind}    os.path.join(ci_run_dir,'gitleaks_summary.json'),",
    f"{ind}  ]",
    f"{ind}  _gl = None",
    f"{ind}  for _p in _gl_paths:",
    f"{ind}    if os.path.exists(_p):",
    f"{ind}      with open(_p, 'r', encoding='utf-8', errors='ignore') as _f:",
    f"{ind}        _gl = json.load(_f)",
    f"{ind}      break",
    f"{ind}  if isinstance(_gl, dict):",
    f"{ind}    status['gitleaks_verdict'] = _gl.get('verdict')",
    f"{ind}    status['gitleaks_total']   = _gl.get('total')",
    f"{ind}    status['gitleaks_counts']  = _gl.get('counts')",
    f"{ind}    status['has_gitleaks']     = True",
    f"{ind}except Exception:",
    f"{ind}  pass",
    "",
])

# Backup then write
bak = target.with_suffix(target.suffix + f".bak_add_gitleaks_{time.strftime('%Y%m%d_%H%M%S')}")
bak.write_text(txt, encoding="utf-8")
print(f"[BACKUP] {bak}")

txt2 = txt[:line_end+1] + "\n" + inject + txt[line_end+1:]
target.write_text(txt2, encoding="utf-8")
print("[OK] injected gitleaks block with indent =", repr(ind))

PY

# compile whole ui to catch syntax errors early
python3 - <<'PY'
import py_compile, sys
from pathlib import Path
root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
bad = []
for f in root.rglob("*.py"):
    try:
        py_compile.compile(str(f), doraise=True)
    except Exception as e:
        bad.append((str(f), str(e)))
if bad:
    print("[ERR] py_compile failures:")
    for f,e in bad[:10]:
        print(" -", f, "=>", e)
    raise SystemExit(4)
print("[OK] py_compile all OK")
PY

echo "DONE"
