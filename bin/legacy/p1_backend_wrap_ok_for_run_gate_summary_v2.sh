#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import re, time, py_compile

TS = time.strftime("%Y%m%d_%H%M%S")
MARK = "VSP_P1_OKWRAP_RUNGATE_SUMMARY_V2"

root = Path(".")
cands = []
for p in root.rglob("*.py"):
    if any(x in p.parts for x in (".venv","venv","node_modules","out","bin")):
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    # prefer files that likely implement the endpoint
    if "run_file_allow" in s and ("/api/vsp/run_file_allow" in s or "def run_file_allow" in s):
        cands.append(p)

if not cands:
    # fallback: any file mentions run_file_allow
    for p in root.rglob("*.py"):
        if any(x in p.parts for x in (".venv","venv","node_modules","out","bin")):
            continue
        s = p.read_text(encoding="utf-8", errors="replace")
        if "run_file_allow" in s:
            cands.append(p)

cands = sorted(set(cands), key=lambda x: (len(str(x)), str(x)))
if not cands:
    raise SystemExit("[ERR] cannot find python file containing run_file_allow")

target = cands[0]
s = target.read_text(encoding="utf-8", errors="replace")

bak = target.with_name(target.name + f".bak_okwrap_v2_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

if MARK in s:
    print("[SKIP] marker already present in", target)
    raise SystemExit(0)

helper = f"""
# ===================== {MARK} =====================
def _vsp_okwrap_gate_summary(payload, rid, path):
    try:
        if not isinstance(payload, dict):
            return payload
        if not path:
            return payload
        if path.endswith("run_gate_summary.json") or path.endswith("run_gate.json"):
            payload.setdefault("ok", True)
            if rid:
                payload.setdefault("rid", rid)
                payload.setdefault("run_id", rid)
        return payload
    except Exception:
        return payload
# ===================== /{MARK} =====================
"""

# insert helper after last import (best effort)
m = list(re.finditer(r"^(?:from\s+\S+\s+import\s+.*|import\s+.*)\s*$", s, flags=re.MULTILINE))
ins = m[-1].end() if m else 0
s = s[:ins] + "\n" + helper + "\n" + s[ins:]

# locate function block def run_file_allow(...)
m = re.search(r"(?m)^(def\s+run_file_allow\s*\(.*?\)\s*:\s*\n)", s)
if not m:
    # try any function containing run_file_allow in name
    m = re.search(r"(?m)^(def\s+\w*run_file_allow\w*\s*\(.*?\)\s*:\s*\n)", s)
if not m:
    raise SystemExit(f"[ERR] cannot locate run_file_allow def in {target}")

start = m.start(1)
# end at next top-level def (same indent 0)
m2 = re.search(r"(?m)^\s*def\s+\w+\s*\(", s[m.end(1):])
end = (m.end(1) + m2.start()) if m2 else len(s)

block = s[start:end]

# patch first "X = json.load(...)" inside this block
pat = re.compile(r"(?m)^(?P<ind>\s*)(?P<var>[A-Za-z_]\w*)\s*=\s*json\.load\s*\(")
m3 = pat.search(block)
if not m3:
    # sometimes uses "import json as _json" etc; fallback to ".load("
    pat2 = re.compile(r"(?m)^(?P<ind>\s*)(?P<var>[A-Za-z_]\w*)\s*=\s*.*?json\.load\s*\(")
    m3 = pat2.search(block)
if not m3:
    raise SystemExit(f"[ERR] cannot find json.load(...) assignment inside run_file_allow in {target}")

ind = m3.group("ind")
var = m3.group("var")

# inject wrap right after that assignment line
lines = block.splitlines(True)
# find the line index containing the matched start
pos = m3.start()
acc = 0
idx = 0
for i, ln in enumerate(lines):
    acc += len(ln)
    if acc > pos:
        idx = i
        break

inject = f"{ind}{var} = _vsp_okwrap_gate_summary({var}, rid, path)\n"
# insert after that line (idx)
lines.insert(idx+1, inject)
block2 = "".join(lines)

s2 = s[:start] + block2 + s[end:]
target.write_text(s2, encoding="utf-8")

py_compile.compile(str(target), doraise=True)
print("[OK] patched python:", target)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] backend ok-wrap v2 applied. Now verify with curl."
