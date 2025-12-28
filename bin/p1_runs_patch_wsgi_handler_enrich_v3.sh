#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_wsgi_enrich_v3_${TS}"
echo "[BACKUP] ${F}.bak_runs_wsgi_enrich_v3_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUNS_WSGI_ENRICH_V3"
if marker in s:
    print("[SKIP] already patched:", marker)
    raise SystemExit(0)

helper = textwrap.dedent(r"""
# --- VSP_P1_RUNS_WSGI_ENRICH_V3 ---
# Enrich /api/vsp/runs response (rid_latest_gate/rid_latest_findings + per-item has.gate/findings).
try:
    from pathlib import Path as __Path
except Exception:
    __Path = None

def __vsp__runs_enrich_v2(data):
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

        data["rid_latest_gate"] = rid_latest_gate
        data["rid_latest_findings"] = rid_latest_findings
        # prefer gate -> findings -> existing rid_latest
        data["rid_latest"] = rid_latest_gate or rid_latest_findings or data.get("rid_latest")
        return data
    except Exception:
        return data
""").strip() + "\n"

s2 = s.rstrip() + "\n\n" + helper

# --- patch multi-line return __vsp__json(...) in the /api/vsp/runs block ---
anchor = "/api/vsp/runs"
idx = s2.find(anchor)
if idx < 0:
    raise SystemExit("[ERR] cannot find /api/vsp/runs anchor")

# find the first "return __vsp__json" after the anchor
ret_kw = "return __vsp__json"
ret_i = s2.find(ret_kw, idx)
if ret_i < 0:
    raise SystemExit("[ERR] cannot find 'return __vsp__json' after /api/vsp/runs")

# locate '(' of __vsp__json(
lp = s2.find("(", ret_i)
if lp < 0:
    raise SystemExit("[ERR] cannot find '(' after return __vsp__json")

# parse until matching ')'
i = lp
depth = 0
in_s = False
in_d = False
esc = False
while i < len(s2):
    ch = s2[i]
    if esc:
        esc = False
    elif ch == "\\":
        esc = True
    elif in_s:
        if ch == "'":
            in_s = False
    elif in_d:
        if ch == '"':
            in_d = False
    else:
        if ch == "'":
            in_s = True
        elif ch == '"':
            in_d = True
        elif ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                rp = i
                break
    i += 1
else:
    raise SystemExit("[ERR] unmatched parentheses for __vsp__json(...)")

# Extract inner expression of __vsp__json( <inner> )
inner = s2[lp+1:rp].strip()
if "__vsp__runs_enrich_v2" in inner:
    raise SystemExit("[SKIP] already wrapped by __vsp__runs_enrich_v2")

new_call = f"return __vsp__json(__vsp__runs_enrich_v2({inner}))"
# replace whole return statement from ret_i to rp+1, keep any trailing whitespace after ')'
# try extend to end-of-line
line_end = s2.find("\n", rp)
if line_end < 0:
    line_end = len(s2)
before = s2[:ret_i]
after = s2[line_end:]
s3 = before + new_call + after

p.write_text(s3, encoding="utf-8")
print("[OK] patched multi-line __vsp__json(...) for /api/vsp/runs")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service

BASE=http://127.0.0.1:8910
echo "== verify /api/vsp/runs?limit=2 (expect rid_latest_gate/findings + item.has.gate/findings) =="
curl -sS "$BASE/api/vsp/runs?limit=2" | head -c 1400; echo
