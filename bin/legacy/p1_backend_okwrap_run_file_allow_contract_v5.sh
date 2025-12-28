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
ROUTE = "/api/vsp/run_file_allow"
MARK  = "VSP_P1_OKWRAP_RUN_FILE_ALLOW_CONTRACT_V5"

def find_handler():
    root = Path(".")
    hits = []
    for p in root.rglob("*.py"):
        if any(x in p.parts for x in (".venv","venv","node_modules","out","bin")):
            continue
        s = p.read_text(encoding="utf-8", errors="replace")
        # match decorators: @app.route("/api/vsp/run_file_allow"...), @app.get("..."), @bp.route("...")
        pat = re.compile(
            r"(?ms)^\s*@.*?(?:route|get|post)\s*\(\s*([rRuUfFbB]?)['\"]"
            + re.escape(ROUTE)
            + r"['\"].*?\)\s*\n\s*def\s+(?P<fn>[A-Za-z_]\w*)\s*\(",
        )
        for m in pat.finditer(s):
            hits.append((p, m.group("fn"), m.start()))
    # prefer shortest path (usually wsgi_vsp_ui_gateway.py or vsp_demo_app.py)
    hits.sort(key=lambda t: (len(str(t[0])), str(t[0]), t[2]))
    return hits[0] if hits else None

hit = find_handler()
if not hit:
    raise SystemExit(f"[ERR] cannot locate decorator for route {ROUTE} in any *.py under this folder")

p, fn, pos = hit
s = p.read_text(encoding="utf-8", errors="replace")
bak = p.with_name(p.name + f".bak_okwrap_v5_{TS}")
bak.write_text(s, encoding="utf-8")
print("[BACKUP]", bak)
print("[TARGET]", p, "handler=", fn)

if MARK in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

# insert helper after last import (best effort)
helper = f"""
# ===================== {MARK} =====================
def _vsp_okwrap_gate_summary(payload, _loc=None):
    try:
        _loc = _loc or {{}}
        _path = (_loc.get("path") or _loc.get("rel_path") or _loc.get("p") or _loc.get("req_path") or "")
        _rid  = (_loc.get("rid")  or _loc.get("run_id") or _loc.get("rid_latest") or "")
        if not _path:
            return payload
        if isinstance(payload, dict) and (str(_path).endswith("run_gate_summary.json") or str(_path).endswith("run_gate.json")):
            payload.setdefault("ok", True)
            if _rid:
                payload.setdefault("rid", _rid)
                payload.setdefault("run_id", _rid)
        return payload
    except Exception:
        return payload
# ===================== /{MARK} =====================
"""

imports = list(re.finditer(r"(?m)^(?:from\s+\S+\s+import\s+.*|import\s+.*)\s*$", s))
ins = imports[-1].end() if imports else 0
s = s[:ins] + "\n" + helper + "\n" + s[ins:]

# locate function block of handler fn
mdef = re.search(r"(?m)^\s*def\s+" + re.escape(fn) + r"\s*\(.*?\)\s*:\s*$", s)
if not mdef:
    raise SystemExit(f"[ERR] cannot find def {fn}(...) line in {p}")

start = mdef.start()
mnext = re.search(r"(?m)^\s*def\s+\w+\s*\(", s[mdef.end():])
end = (mdef.end() + mnext.start()) if mnext else len(s)
block = s[start:end]

# Patch return jsonify(VAR) inside this handler: wrap VAR with okwrap (locals)
# Support: return jsonify(x) or return flask.jsonify(x)
pat = re.compile(r"(?m)^(?P<ind>\s*)return\s+(?:flask\.)?jsonify\s*\(\s*(?P<var>[A-Za-z_]\w*)\s*\)\s*$")
def _repl(m):
    ind = m.group("ind")
    var = m.group("var")
    return f"{ind}{var} = _vsp_okwrap_gate_summary({var}, locals())\n{ind}return jsonify({var})"

block2, n = pat.subn(_repl, block)
if n == 0:
    # fallback: sometimes alias is j, data; but return line may include extra args -> try broader but still safe (single var only)
    raise SystemExit(f"[ERR] handler found but no simple 'return jsonify(VAR)' line to patch in {p}. Need alternate patch point.")

s2 = s[:start] + block2 + s[end:]
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] patched:", p, "jsonify_wrapped=", n)
PY

systemctl restart vsp-ui-8910.service 2>/dev/null || true
echo "[DONE] v5 ok-wrap applied. Now verify with curl."
