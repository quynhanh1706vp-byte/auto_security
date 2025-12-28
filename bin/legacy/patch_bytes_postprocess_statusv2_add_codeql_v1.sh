#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bytes_codeql_${TS}"
echo "[BACKUP] $F.bak_bytes_codeql_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_CODEQL_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Find the gitleaks bytes postprocess block location to insert near it
anchor = "VSP_WSGI_BYTES_POSTPROCESS_STATUSV2_GITLEAKS_V1"
pos = t.find(anchor)
if pos < 0:
    print("[ERR] cannot find anchor:", anchor)
    raise SystemExit(2)

# From anchor forward, find a good insertion point after gitleaks fields are set.
# We'll insert after the first occurrence of 'gitleaks_total' assignment within this area.
sub = t[pos:]
m = re.search(r'(?m)^\s*data\[[\'"]gitleaks_total[\'"]\]\s*=', sub)
if not m:
    # fallback: insert after 'has_gitleaks'
    m = re.search(r'(?m)^\s*data\[[\'"]has_gitleaks[\'"]\]\s*=', sub)
if not m:
    print("[ERR] cannot locate gitleaks assignment block to hook")
    raise SystemExit(3)

ins_at = pos + m.end()
# Determine indent from that line
line_start = sub.rfind("\n", 0, m.start()) + 1
line = sub[line_start: sub.find("\n", line_start)]
indent = re.match(r'^(\s*)', line).group(1)

block = f"""
{indent}{TAG}
{indent}# Fill CodeQL fields for UI binding (runs in bytes-postprocess so it wins)
{indent}try:
{indent}    import os, json
{indent}    # defaults (never null)
{indent}    data["has_codeql"] = bool(data.get("has_codeql") or False)
{indent}    data["codeql_verdict"] = data.get("codeql_verdict") or None
{indent}    try:
{indent}        data["codeql_total"] = int(data.get("codeql_total") or 0)
{indent}    except Exception:
{indent}        data["codeql_total"] = 0
{indent}
{indent}    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or ""
{indent}    codeql_dir = os.path.join(ci, "codeql") if ci else ""
{indent}    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""
{indent}
{indent}    # 1) Prefer real summary file
{indent}    if summary and os.path.isfile(summary):
{indent}        try:
{indent}            j = json.load(open(summary, "r", encoding="utf-8"))
{indent}        except Exception:
{indent}            j = {{}}
{indent}        data["has_codeql"] = True
{indent}        data["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict") or "AMBER"
{indent}        try:
{indent}            data["codeql_total"] = int(j.get("total") or 0)
{indent}        except Exception:
{indent}            data["codeql_total"] = 0
{indent}    else:
{indent}        # 2) Fallback from run_gate_summary.by_tool.CODEQL (already present in your payload)
{indent}        rg = data.get("run_gate_summary") or {{}}
{indent}        bt = (rg.get("by_tool") or {{}})
{indent}        cq = bt.get("CODEQL") or bt.get("CodeQL") or {{}}
{indent}        if isinstance(cq, dict) and cq:
{indent}            data["has_codeql"] = True
{indent}            data["codeql_verdict"] = cq.get("verdict") or "AMBER"
{indent}            try:
{indent}                data["codeql_total"] = int(cq.get("total") or 0)
{indent}            except Exception:
{indent}                data["codeql_total"] = 0
{indent}        else:
{indent}            # 3) Fallback by sarif presence
{indent}            if codeql_dir and os.path.isdir(codeql_dir):
{indent}                sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
{indent}                if sarifs:
{indent}                    data["has_codeql"] = True
{indent}                    data["codeql_verdict"] = data.get("codeql_verdict") or "AMBER"
{indent}
{indent}    # Normalize gate schema for UI (optional but helps): overall_verdict from run_gate_summary.overall
{indent}    if (not data.get("overall_verdict")) and isinstance(data.get("run_gate_summary"), dict):
{indent}        ov = (data["run_gate_summary"].get("overall") or "").strip()
{indent}        if ov:
{indent}            data["overall_verdict"] = ov
{indent}except Exception:
{indent}    pass
"""

t2 = t[:ins_at] + block + t[ins_at:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted CodeQL bytes-postprocess block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f out_ci/ui_8910.lock 2>/dev/null || true
bin/restart_8910_gunicorn_commercial_v5.sh

echo "== VERIFY =="
RID="RUN_VSP_CI_20251215_034956"
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/$RID" \
 | jq '{ok, has_codeql, codeql_verdict, codeql_total, has_gitleaks, gitleaks_total, overall_verdict, gate_codeql:(.run_gate_summary.by_tool.CODEQL//null)}'
