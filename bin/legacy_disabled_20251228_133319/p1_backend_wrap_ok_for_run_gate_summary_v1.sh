#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

# find python file that defines /api/vsp/run_file_allow
root = Path(".")
cands = []
for p in root.rglob("*.py"):
    if any(x in p.parts for x in (".venv","venv","node_modules","out","bin")): 
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "/api/vsp/run_file_allow" in s or "run_file_allow" in s:
        if "def" in s and "run_file_allow" in s:
            cands.append(p)

if not cands:
    # fallback: any file containing the string
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
bak = target.with_name(target.name + f".bak_okwrap_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)

MARK = "VSP_P1_OKWRAP_RUNGATE_SUMMARY_V1"
if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# insert code near the place where content is loaded as JSON dict before jsonify/return
# We try to locate a json load into variable and return jsonify(var).
# If not found, we still inject a small helper and a late hook just before return.

helper = f"""
# ===================== {MARK} =====================
def _vsp_okwrap_gate_summary(payload, rid, path):
    try:
        if not isinstance(payload, dict):
            return payload
        if not path:
            return payload
        if path.endswith("run_gate_summary.json") or path.endswith("run_gate.json"):
            if "ok" not in payload:
                payload["ok"] = True
            if rid and "rid" not in payload:
                payload["rid"] = rid
            if rid and "run_id" not in payload:
                payload["run_id"] = rid
        return payload
    except Exception:
        return payload
# ===================== /{MARK} =====================
"""

# put helper near top after imports (best effort)
if "import" in s:
    # after last import block
    m = list(re.finditer(r"^(?:from\s+\S+\s+import\s+.*|import\s+.*)\s*$", s, flags=re.MULTILINE))
    if m:
        ins = m[-1].end()
        s = s[:ins] + "\n" + helper + "\n" + s[ins:]
else:
    s = helper + "\n" + s

# now hook: before returning jsonify(payload)
# common patterns: return jsonify(obj)  OR  return flask.jsonify(obj)
hooked = False
patterns = [
    r"return\s+jsonify\((?P<var>[a-zA-Z_][a-zA-Z0-9_]*)\)",
    r"return\s+flask\.jsonify\((?P<var>[a-zA-Z_][a-zA-Z0-9_]*)\)",
]
for pat in patterns:
    m = re.search(pat, s)
    if m:
        var = m.group("var")
        repl = f"{var} = _vsp_okwrap_gate_summary({var}, rid, path)\n    " + m.group(0)
        s = re.sub(pat, repl, s, count=1)
        hooked = True
        break

# fallback: if return jsonify is inline (jsonify({...})) we hook by wrapping right before return line
if not hooked:
    # find handler function for run_file_allow and add a line just before 'return'
    m = re.search(r"def\s+run_file_allow\s*\(.*?\)\s*:\s*(?P<body>(?:.|\n)*?)\n(?=def\s|\Z)", s)
    if m:
        body = m.group("body")
        # add before first 'return'
        s = re.sub(r"(def\s+run_file_allow\s*\(.*?\)\s*:\s*\n)", r"\1    # "+MARK+"\n", s, count=1)
        s = re.sub(r"\n(\s*)return\s+", r"\n\1payload = locals().get('payload') or locals().get('j') or locals().get('data')\n\1try:\n\1    payload = _vsp_okwrap_gate_summary(payload, rid, path)\n\1    if 'payload' in locals():\n\1        pass\n\1except Exception:\n\1    pass\n\1return ", s, count=1)
        hooked = True

target.write_text(s, encoding="utf-8")
py_compile.compile(str(target), doraise=True)
print("[OK] patched python:", target)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] backend ok-wrap applied. Now verify with curl (should ok:true)."
