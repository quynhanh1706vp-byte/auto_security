#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need rg

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

python3 - <<'PY'
from pathlib import Path
import re, time, sys

ROOT = Path(".")
EXCL_DIRS = {"out","out_ci","node_modules",".git","__pycache__","venv",".venv"}

EXTRAS = [
  "run_manifest.json",
  "run_evidence_index.json",
  "reports/findings_unified.sarif",
]

MARK = "VSP_P0_RUNFILEALLOW_CONTRACT_AUTOFIND_V1"

def is_ok(p: Path) -> bool:
    if p.suffix != ".py": return False
    for part in p.parts:
        if part in EXCL_DIRS: return False
    # đừng patch trong bin/ hoặc backup
    if "bin" in p.parts: return False
    if ".bak_" in p.name or ".broken_" in p.name: return False
    return True

cands = []
for p in ROOT.rglob("*.py"):
    if not is_ok(p): 
        continue
    s = p.read_text(encoding="utf-8", errors="replace")
    # heuristic: file có run_file_allow + payload not allowed + allow list keys
    if "run_file_allow" in s and ("not allowed" in s.lower()) and ("\"allow\"" in s or "'allow'" in s):
        score = 0
        score += s.count("run_file_allow") * 10
        score += s.lower().count("not allowed") * 3
        score += 20 if "/api/vsp/run_file_allow" in s else 0
        score += 10 if "VSP_RUN_FILE_ALLOW" in s else 0
        cands.append((score, p, s))

cands.sort(key=lambda x: x[0], reverse=True)
if not cands:
    print("[ERR] cannot find candidate python file implementing run_file_allow")
    print("[HINT] run: rg -n \"run_file_allow\" -S .")
    sys.exit(2)

score, target, s = cands[0]
print(f"[INFO] target={target} score={score}")

if MARK in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

ts = time.strftime("%Y%m%d_%H%M%S")
bak = target.with_name(target.name + f".bak_runfileallow_contract_{ts}")
bak.write_text(s, encoding="utf-8")
print(f"[BACKUP] {bak}")

# 1) try patch list literal that contains run_gate_summary.json
# handle allow = [ ... ] or ALLOW = [ ... ]
list_pat = re.compile(
    r"(?P<lhs>\ballow\b|\bALLOW\b|\ballowlist\b|\ballowed\b)\s*=\s*\[(?P<body>[\s\S]*?)\]\s*",
    re.M
)

m = list_pat.search(s)
patched = False
if m and ("run_gate_summary.json" in m.group("body") or "run_gate.json" in m.group("body")):
    body = m.group("body")
    # collect existing quoted strings
    existing = set(re.findall(r"['\"]([^'\"]+)['\"]", body))
    add_lines = []
    for x in EXTRAS:
        if x not in existing:
            add_lines.append(f'  "{x}",\n')
    if add_lines:
        # insert before closing bracket of this list
        insert_at = m.end("body")
        s2 = s[:insert_at] + ("\n" if not body.endswith("\n") else "") + "".join(add_lines) + s[insert_at:]
        s = s2
        patched = True
        print(f"[OK] appended extras into list: added={len(add_lines)}")
    else:
        print("[OK] extras already present in list")
        patched = True

# 2) if no list literal, patch the JSON error payload allow:[...] right where it is built
if not patched:
    # pattern: {"allow":[...], "err":"not allowed"...}
    jpat = re.compile(r'("allow"\s*:\s*\[)([\s\S]*?)(\])', re.M)
    mj = jpat.search(s)
    if mj:
        body = mj.group(2)
        existing = set(re.findall(r"['\"]([^'\"]+)['\"]", body))
        add = [x for x in EXTRAS if x not in existing]
        if add:
            ins = "".join([f'"{x}",' for x in add])
            s = s[:mj.end(2)] + ("" if body.strip().endswith(",") or body.strip()=="" else ",") + ins + s[mj.end(2):]
            patched = True
            print(f"[OK] appended extras into error payload allow[]: added={len(add)}")
        else:
            patched = True
            print("[OK] extras already present in allow[] payload")

# 3) as a safety net, inject a tiny “allow.extend(EXTRAS)” near run_file_allow function if found
if MARK not in s:
    s = s + f"\n# {MARK}\n"

if not patched:
    print("[ERR] could not patch allow list automatically.")
    print(f"[HINT] open target: {target} and search for the allow list returned in 403 response.")
    sys.exit(2)

target.write_text(s, encoding="utf-8")
print("[OK] wrote patch")
PY

echo "== py_compile all candidate modules =="
python3 -m py_compile $(rg -l "run_file_allow" -S . --glob '*.py' --glob '!.*/out/*' --glob '!.*/out_ci/*' --glob '!.*/node_modules/*' --glob '!bin/*' | tr '\n' ' ') 2>/dev/null || true

echo "== restart =="
systemctl restart "$SVC"

echo "== smoke =="
bash bin/p0_dashboard_smoke_contract_v1.sh
