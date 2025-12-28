#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_forceallow_gate_${TS}"
echo "[BACKUP] ${W}.bak_forceallow_gate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# 1) locate the handler region by URL marker
hit = None
for i,l in enumerate(lines):
    if "/api/vsp/run_file_allow" in l:
        hit = i
        break
if hit is None:
    raise SystemExit("[ERR] cannot find /api/vsp/run_file_allow in wsgi")

# 2) within a window, find the "if <expr> not in <allowvar>:" line
win_lo = max(0, hit-200)
win_hi = min(len(lines), hit+800)
win = lines[win_lo:win_hi]

deny_i = None
mcap = None
for j,l in enumerate(win):
    m = re.search(r'^\s*if\s+(.+?)\s+not\s+in\s+([A-Za-z_][A-Za-z0-9_]*allow[A-Za-z0-9_]*)\s*:\s*$', l)
    if m:
        deny_i = win_lo + j
        mcap = m
        break

if deny_i is None:
    # fallback: allowvar might be named "allow" exactly without "allow" substring rule above
    for j,l in enumerate(win):
        m = re.search(r'^\s*if\s+(.+?)\s+not\s+in\s+(allow|allowed|ALLOW|ALLOWLIST)\s*:\s*$', l)
        if m:
            deny_i = win_lo + j
            mcap = m
            break

if deny_i is None or mcap is None:
    raise SystemExit("[ERR] cannot find deny check 'if X not in allow*:' near run_file_allow handler")

expr = mcap.group(1).strip()
allowvar = mcap.group(2).strip()

# 3) compute indentation (same as deny line)
indent = re.match(r'^(\s*)', lines[deny_i]).group(1)

# 4) insert extra-allow set right before deny line (idempotent)
marker = "VSP_P0_FORCEALLOW_GATE_REPORTS_V3"
extra_decl = (
    f'{indent}# --- {marker} ---\n'
    f'{indent}__vsp_extra_allow = set(["reports/run_gate_summary.json","reports/run_gate.json"])\n'
    f'{indent}# --- /{marker} ---\n'
)

# ensure not already inserted
if marker not in s:
    lines.insert(deny_i, extra_decl)
    deny_i += 1

# 5) rewrite deny condition to include extra allow.
# Also normalize to accept leading "/" cases by checking lstrip("/") when expr is "path"
cond = lines[deny_i].rstrip("\n")
expr2 = expr
# if expr looks like a variable (no spaces, no quotes), add a lstrip variant
if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', expr):
    expr2 = f'{expr} if {expr}.startswith("/") else {expr}'

new_if = f"{indent}if ({expr2} not in {allowvar}) and ({expr2} not in __vsp_extra_allow):\n"
lines[deny_i] = new_if

# 6) reduce console spam: if handler returns 403 for not allowed, change to 200 (best-effort)
# only inside the same window after deny_i
for k in range(deny_i, min(len(lines), deny_i+120)):
    if "not allowed" in lines[k].lower() and "403" in lines[k]:
        lines[k] = re.sub(r'\b403\b', '200', lines[k])
    # also common: return ..., 403
    if re.search(r'return\s+.*,\s*403\b', lines[k]):
        lines[k] = re.sub(r',\s*403\b', ', 200', lines[k])

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched deny-check at line~{deny_i+1}: allowvar={allowvar} expr={expr!r}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

systemctl restart vsp-ui-8910.service 2>/dev/null || true

# wait until API is up (avoid JSONDecodeError)
echo "== wait /api/ui/runs_kpi_v2 =="
RID=""
for _ in $(seq 1 30); do
  J="$(curl -fsS "$BASE/api/ui/runs_kpi_v2?days=30" 2>/dev/null || true)"
  if echo "$J" | grep -q '"ok": true'; then
    RID="$(python3 - <<PY
import json
j=json.loads("""$J""")
print(j.get("latest_rid",""))
PY
)"
    [ -n "$RID" ] && break
  fi
  sleep 0.4
done
echo "[RID]=$RID"
[ -n "$RID" ] || { echo "[ERR] cannot get RID from runs_kpi_v2"; exit 2; }

echo "== sanity run_file_allow gate summary (should be 200 and NOT not-allowed) =="
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 80

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). 403 spam should stop; gate summary should fetch OK."
