#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_contractforce_${TS}"
echo "[BACKUP] ${W}.bak_contractforce_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1"
if MARK not in s:
    # inject contract helper if missing (safe)
    contract_block = r'''
# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
# Dashboard minimal whitelist (exact paths; no glob)
_DASHBOARD_ALLOW_EXACT = {
  "run_gate_summary.json",
  "findings_unified.json",
  "run_gate.json",
  "run_manifest.json",
  "run_evidence_index.json",
  "reports/findings_unified.csv",
  "reports/findings_unified.sarif",
  "reports/findings_unified.html",
}
def _dash_allow_exact(path: str) -> bool:
  try:
    p = (path or "").strip().lstrip("/")
    if not p: return False
    if ".." in p: return False
    if p.startswith(("/", "\\")): return False
    return p in _DASHBOARD_ALLOW_EXACT
  except Exception:
    return False
# ===================== /VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================
'''
    m = re.search(r"^(import\s.+|from\s.+import\s.+)\n(?:import\s.+\n|from\s.+import\s.+\n)*", s, flags=re.M)
    if m:
        s = s[:m.end()] + contract_block + "\n" + s[m.end():]
    else:
        s = contract_block + "\n" + s

# locate run_file_allow route area (limit edits to that block)
idx = s.find("run_file_allow")
if idx < 0:
    print("[ERR] cannot find 'run_file_allow' in file")
    sys.exit(2)

# take a window around it to avoid touching unrelated endpoints
start = max(0, idx - 1500)
end   = min(len(s), idx + 20000)
seg = s[start:end]

# marker for this force patch
MARK2 = "VSP_P0_RUNFILEALLOW_FORCE_CONTRACT_IN_HANDLER_V2"
if MARK2 in seg:
    print("[OK] force marker already present; skip")
    p.write_text(s, encoding="utf-8")
    sys.exit(0)

# We want: if not allowed: return not allowed  ==> if not allowed: if not _dash_allow_exact(path): return not allowed; allowed=True
# Apply only inside the run_file_allow handler window.
pat = re.compile(
    r"""
(?P<ifline>^[ \t]*if[ \t]+not[ \t]+allowed[ \t]*:[ \t]*\n)
(?P<indent>[ \t]+)
(?P<ret>return[^\n]*not[ \t]+allowed[^\n]*\n)
""",
    re.M | re.X | re.I
)

m = pat.search(seg)
repls = 0
if m:
    indent = m.group("indent")
    new = (
        f"{m.group('ifline')}"
        f"{indent}# {MARK2}: dashboard contract bypass\n"
        f"{indent}if not _dash_allow_exact(path):\n"
        f"{indent}  {m.group('ret').lstrip()}"
        f"{indent}allowed = True\n"
    )
    seg2 = seg[:m.start()] + new + seg[m.end():]
    repls += 1
else:
    # fallback: pattern with direct is_allowed(...) return not allowed
    pat2 = re.compile(
        r"""
^[ \t]*if[ \t]+not[ \t]+(?P<fn>[a-zA-Z_][a-zA-Z0-9_]*)\(\s*path\s*\)\s*:[ \t]*\n
(?P<indent>[ \t]+)
(?P<ret>return[^\n]*not[ \t]+allowed[^\n]*\n)
""",
        re.M | re.X | re.I
    )
    m2 = pat2.search(seg)
    if m2:
        fn = m2.group("fn")
        indent = m2.group("indent")
        new = (
            f"if (not _dash_allow_exact(path)) and (not {fn}(path)):\n"
            f"{indent}{m2.group('ret').lstrip()}"
        )
        seg2 = seg[:m2.start()] + new + seg[m2.end():]
        repls += 1
    else:
        seg2 = seg

if repls == 0:
    print("[WARN] could not patch handler with known patterns. Need manual locate.")
else:
    print(f"[OK] patched run_file_allow handler rewrites={repls}")

# drop a marker comment near the route occurrence for traceability
insert_pos = seg2.find("run_file_allow")
if insert_pos >= 0:
    seg2 = seg2[:insert_pos] + f"\n# {MARK2}\n" + seg2[insert_pos:]

s2 = s[:start] + seg2 + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] wrote wsgi patch")
PY

echo "== py_compile =="
python3 -m py_compile wsgi_vsp_ui_gateway.py

echo "== restart =="
systemctl restart "$SVC"

echo "== re-smoke core =="
bash bin/p0_dashboard_smoke_contract_v1.sh
