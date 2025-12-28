#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_statusv2_tools_v2_${TS}"
echo "[BACKUP] $F.bak_statusv2_tools_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUSV2_BUILD_TOOLS_ALWAYS8_V2 ==="
if TAG in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

# find the route handler that serves /api/vsp/run_status_v2
# pattern: route('/api/vsp/run_status_v2/<rid>') then def xxx(...):
m = re.search(r"(@.*?/api/vsp/run_status_v2[^\n]*\n(?:@.*\n)*)\s*def\s+([A-Za-z0-9_]+)\s*\(", s)
if not m:
    print("[ERR] cannot locate /api/vsp/run_status_v2 route in vsp_demo_app.py")
    raise SystemExit(2)

func_name = m.group(2)
print("[INFO] found handler:", func_name)

# slice function block (from def to next top-level def/@)
start = s.find(f"def {func_name}", m.end())
if start < 0:
    raise SystemExit(3)

# find end of function by next "\ndef " or "\n@" at col 0
m_end = re.search(r"\n(?=def\s|\@)", s[start:])
end = start + (m_end.start() if m_end else len(s))

block = s[start:end]

# find first return jsonify(...) inside block (may span multiple lines)
ret = re.search(r"\n\s*return\s+jsonify\((?P<expr>[\s\S]*?)\)\s*\n", block)
if not ret:
    print("[ERR] cannot find 'return jsonify(...)' inside status_v2 handler")
    raise SystemExit(4)

expr = ret.group("expr").strip()

inject = f"""
{TAG}
    # commercial invariant: expose unified tool lanes in payload
    _out = {expr}
    if not isinstance(_out, dict):
        try:
            _out = dict(_out)
        except Exception:
            _out = {{"ok": False, "error": "status_v2_payload_not_dict"}}

    _CANON = ["SEMGREP","GITLEAKS","TRIVY","CODEQL","KICS","GRYPE","SYFT","BANDIT"]
    _ZERO = {{"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0,"INFO":0,"TRACE":0}}

    def _norm_counts(c):
        d = dict(_ZERO)
        if isinstance(c, dict):
            for k,v in c.items():
                kk = str(k).upper()
                if kk in d:
                    try: d[kk] = int(v)
                    except Exception: d[kk] = 0
        return d

    def _mk(tool, has_key=None, total_key=None, verdict_key=None, counts_key=None):
        hasv = bool(_out.get(has_key)) if has_key else None
        total = _out.get(total_key, 0) if total_key else 0
        verdict = _out.get(verdict_key) if verdict_key else None
        counts = _norm_counts(_out.get(counts_key, {{}})) if counts_key else dict(_ZERO)

        # decide status/verdict
        if hasv is False:
            return {{
                "tool": tool, "status": "NOT_RUN", "verdict": "NOT_RUN",
                "total": 0, "counts": dict(_ZERO), "reason": "has_flag_false"
            }}
        if verdict is None and total == 0 and counts == _ZERO:
            return {{
                "tool": tool, "status": "NOT_RUN", "verdict": "NOT_RUN",
                "total": 0, "counts": dict(_ZERO), "reason": "missing_fields"
            }}

        vv = str(verdict).upper() if verdict is not None else "OK"
        return {{
            "tool": tool,
            "status": vv,
            "verdict": vv,
            "total": int(total) if str(total).isdigit() else (total or 0),
            "counts": counts
        }}

    tools = {{}}
    tools["CODEQL"]  = _mk("CODEQL",  "has_codeql",  "codeql_total",  "codeql_verdict",  None)
    tools["GITLEAKS"]= _mk("GITLEAKS","has_gitleaks","gitleaks_total","gitleaks_verdict","gitleaks_counts")
    tools["SEMGREP"] = _mk("SEMGREP", "has_semgrep","semgrep_total", "semgrep_verdict", "semgrep_counts")
    tools["TRIVY"]   = _mk("TRIVY",   "has_trivy",  "trivy_total",   "trivy_verdict",   "trivy_counts")

    # tools not present in flat payload -> NOT_RUN
    for _t in ["KICS","GRYPE","SYFT","BANDIT"]:
        tools[_t] = tools.get(_t) or {{
            "tool": _t, "status": "NOT_RUN", "verdict": "NOT_RUN",
            "total": 0, "counts": dict(_ZERO), "reason": "no_converter_yet"
        }}

    # publish tools + stable order
    _out["tools"] = tools
    _out["tools_order"] = _CANON

    # also force gate summary to include all tools (UI often reads this)
    _gs = _out.get("run_gate_summary")
    if not isinstance(_gs, dict):
        _gs = {{}}
    for _t in _CANON:
        if _t not in _gs:
            _gs[_t] = {{
                "tool": _t,
                "verdict": tools[_t].get("verdict","NOT_RUN"),
                "total": tools[_t].get("total",0)
            }}
    _out["run_gate_summary"] = _gs

    return jsonify(_out)
"""

# Replace old return jsonify(...) with injected block
new_block = block[:ret.start()] + "\n" + inject + "\n" + block[ret.end():]
s2 = s[:start] + new_block + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched status_v2 handler to include .tools + gate_summary always-8")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile"
echo "[DONE] patched $F. Restart 8910 now."
