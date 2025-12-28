#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_wsgi_enrich_${TS}"
echo "[BACKUP] ${F}.bak_runs_wsgi_enrich_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_WSGI_ENRICH_V2"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

helper = textwrap.dedent(r"""
# --- VSP_P1_RUNS_WSGI_ENRICH_V2 ---
# Enrich /api/vsp/runs at WSGI router layer (because not all builds expose __vsp__runs_payload symbol).
try:
    import os as __os
    import json as __json
    from pathlib import Path as __Path
except Exception:
    __os = None
    __json = None
    __Path = None

def __vsp__runs_enrich_v2(data):
    # data is expected dict from runs listing
    try:
        if not isinstance(data, dict) or not isinstance(data.get("items"), list):
            return data
        roots = data.get("roots_used") or []
        items = data["items"]

        gate_candidates = [
            "run_gate_summary.json",
            "reports/run_gate_summary.json",
            "run_gate.json",
            "reports/run_gate.json",
        ]
        findings_candidates = [
            "reports/findings_unified.json",
            "findings_unified.json",
        ]

        rid_latest_gate = None
        rid_latest_findings = None

        def find_run_dir(rid: str):
            if not __Path:
                return None
            for r in roots:
                if not r:
                    continue
                cand = __Path(r) / rid
                if cand.exists():
                    return cand
            return None

        for it in items:
            if not isinstance(it, dict):
                continue
            rid = it.get("run_id")
            if not rid:
                continue
            rd = find_run_dir(rid)
            has_gate = False
            has_findings = False

            if rd is not None:
                for rel in gate_candidates:
                    if (rd / rel).exists():
                        has_gate = True
                        break
                for rel in findings_candidates:
                    if (rd / rel).exists():
                        has_findings = True
                        break

            it.setdefault("has", {})
            it["has"]["gate"] = bool(has_gate)
            it["has"]["findings"] = bool(has_findings)

            if rid_latest_gate is None and has_gate:
                rid_latest_gate = rid
            if rid_latest_findings is None and has_findings:
                rid_latest_findings = rid

            if rid_latest_gate and rid_latest_findings:
                # early stop if both found
                pass

        data["rid_latest_gate"] = rid_latest_gate
        data["rid_latest_findings"] = rid_latest_findings
        data["rid_latest"] = rid_latest_gate or rid_latest_findings or data.get("rid_latest")
        return data
    except Exception:
        return data
""").strip() + "\n"

# Insert helper near end (safe)
s2 = s.rstrip() + "\n\n" + helper

# Now patch the /api/vsp/runs return line near the router block
lines = s2.splitlines(True)

# Find an anchor line containing "/api/vsp/runs"
anchors = [i for i,l in enumerate(lines) if "/api/vsp/runs" in l]
if not anchors:
    raise SystemExit("[ERR] cannot find /api/vsp/runs in file")

patched = 0
for ai in anchors[:5]:
    # scan forward a bit for a single-line `return __vsp__json(...)`
    for j in range(ai, min(ai+140, len(lines))):
        lj = lines[j]
        if "return __vsp__json(" in lj:
            # only patch simple one-line returns ending with ')'
            if lj.strip().endswith(")"):
                # extract inner expr between first '(' after __vsp__json and last ')'
                m = re.search(r"return\s+__vsp__json\(\s*(.+?)\s*\)\s*$", lj)
                if not m:
                    continue
                expr = m.group(1)
                # avoid double wrapping
                if "__vsp__runs_enrich_v2" in expr:
                    continue
                lines[j] = re.sub(
                    r"return\s+__vsp__json\(\s*(.+?)\s*\)\s*$",
                    r"return __vsp__json(__vsp__runs_enrich_v2(\1))",
                    lj
                )
                patched += 1
                break
    if patched:
        break

if patched == 0:
    raise SystemExit("[ERR] found /api/vsp/runs but could not patch return __vsp__json(...) line (maybe multi-line).")

out = "".join(lines)
p.write_text(out, encoding="utf-8")
print("[OK] patched runs return lines:", patched)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service

BASE=http://127.0.0.1:8910
echo "== verify /api/vsp/runs?limit=2 (expect rid_latest_gate/findings) =="
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 1200; echo
