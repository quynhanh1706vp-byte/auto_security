#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrap_status_${TS}"
echo "[BACKUP] $F.bak_wrap_status_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_WRAP_STATUS_V1V2_POSTPROCESS_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

# --- inject helpers (top-level) ---
helper = r'''
# === VSP_WRAP_STATUS_V1V2_POSTPROCESS_V1 ===
def _vsp__safe_json_from_response(ret):
    """Return (data, is_response) where data is dict if possible."""
    try:
        # Flask Response from jsonify has get_json
        if hasattr(ret, "get_json"):
            data = ret.get_json(silent=True)
            if isinstance(data, dict):
                return data, True
    except Exception:
        pass
    if isinstance(ret, dict):
        return ret, False
    return None, False

def _vsp__resolve_rid_from_locals(loc):
    try:
        for k in ("req_id","REQ_ID","request_id","RID","rid","id"):
            v = loc.get(k)
            if isinstance(v, str) and v:
                return v
    except Exception:
        pass
    # fallback: try flask request.path
    try:
        from flask import request
        path = getattr(request, "path", "") or ""
        if path:
            return path.rstrip("/").split("/")[-1]
    except Exception:
        pass
    return None

def _vsp__pick_latest_ci_dir():
    import glob, os
    pats = [
        "/home/test/Data/*/out_ci/VSP_CI_*",
        "/home/test/Data/SECURITY-10-10-v4/out_ci/VSP_CI_*",
        "/home/test/Data/SECURITY-10-10-v4/out_ci/*VSP_CI_*",
    ]
    cands = []
    for pat in pats:
        cands.extend(glob.glob(pat))
    cands = [c for c in cands if os.path.isdir(c)]
    cands.sort(reverse=True)
    return cands[0] if cands else ""

def _vsp__uireq_state_paths(rid):
    import os
    base = os.path.join(os.path.dirname(__file__), "out_ci")
    return (
        os.path.join(base, "uireq_v1", f"{rid}.json"),
        os.path.join(base, "ui_req_state", f"{rid}.json"),
        os.path.join(base, "ui_req_state_v1", f"{rid}.json"),
    )

def _vsp__read_json(path):
    import json
    try:
        return json.load(open(path, "r", encoding="utf-8"))
    except Exception:
        return None

def _vsp__write_json(path, obj):
    import os, json
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        open(path, "w", encoding="utf-8").write(json.dumps(obj, ensure_ascii=False, indent=2))
        return True
    except Exception:
        return False

def _vsp__postprocess_status_v1(ret, loc):
    import datetime, os
    rid = _vsp__resolve_rid_from_locals(loc) or ""
    data, is_resp = _vsp__safe_json_from_response(ret)
    if not isinstance(data, dict):
        return ret

    # normalize keys
    data.setdefault("stage_name", data.get("stage_name") or "")
    data.setdefault("ci_run_dir", data.get("ci_run_dir") or "")
    data.setdefault("pct", data.get("pct") if data.get("pct") is not None else None)

    # resolve ci_run_dir if empty via persisted uireq state; else fallback latest CI dir
    if not data.get("ci_run_dir") and rid:
        p_uireq, p_old1, p_old2 = _vsp__uireq_state_paths(rid)
        for sp in (p_uireq, p_old1, p_old2):
            if os.path.isfile(sp):
                j = _vsp__read_json(sp) or {}
                data["ci_run_dir"] = j.get("ci_run_dir") or j.get("ci") or j.get("run_dir") or ""
                if data["ci_run_dir"]:
                    break

    if not data.get("ci_run_dir"):
        data["ci_run_dir"] = _vsp__pick_latest_ci_dir()

    # persist uireq_v1 state every call (commercial contract)
    if rid:
        p_uireq, _, _ = _vsp__uireq_state_paths(rid)
        payload = dict(data)
        payload["req_id"] = rid
        payload["ts_persist"] = datetime.datetime.utcnow().isoformat() + "Z"
        _vsp__write_json(p_uireq, payload)

    # if original was Response, re-jsonify to include new fields
    if is_resp:
        try:
            from flask import jsonify
            return jsonify(data)
        except Exception:
            return ret
    return data

def _vsp__postprocess_status_v2(ret, loc):
    import os, json
    data, is_resp = _vsp__safe_json_from_response(ret)
    if not isinstance(data, dict):
        return ret

    # locate ci_run_dir from returned payload
    ci = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir") or ""
    codeql_dir = os.path.join(ci, "codeql") if ci else ""
    summary = os.path.join(codeql_dir, "codeql_summary.json") if codeql_dir else ""

    data.setdefault("has_codeql", False)
    data.setdefault("codeql_verdict", None)
    data.setdefault("codeql_total", 0)

    try:
        if codeql_dir and os.path.isdir(codeql_dir):
            if os.path.isfile(summary):
                try:
                    j = json.load(open(summary, "r", encoding="utf-8"))
                except Exception:
                    j = {}
                data["has_codeql"] = True
                data["codeql_verdict"] = j.get("verdict") or j.get("overall_verdict") or "AMBER"
                try:
                    data["codeql_total"] = int(j.get("total") or 0)
                except Exception:
                    data["codeql_total"] = 0
            else:
                sarifs = [x for x in os.listdir(codeql_dir) if x.lower().endswith(".sarif")]
                if sarifs:
                    data["has_codeql"] = True
                    data["codeql_verdict"] = data.get("codeql_verdict") or "AMBER"
    except Exception:
        pass

    if is_resp:
        try:
            from flask import jsonify
            return jsonify(data)
        except Exception:
            return ret
    return data
'''

# inject helper after imports (best-effort: after first blank line following imports)
if TAG not in t:
    # place after last top import block
    m = list(re.finditer(r'(?m)^(?:import|from)\s+.+$', t))
    ins = m[-1].end() if m else 0
    t = t[:ins] + "\n\n" + helper + "\n" + t[ins:]

def wrap_handler(which: str, post_fn: str):
    global t
    # find handler by route decorator first, else function name
    route_m = re.search(r'(?m)^\s*@.*route\(\s*[\'"][^\'"]*'+re.escape(which)+r'[^\'"]*[\'"]', t)
    start = None
    if route_m:
        mdef = re.search(r'(?m)^\s*def\s+\w+\s*\(', t[route_m.start():])
        if mdef:
            start = route_m.start() + mdef.start()
    if start is None:
        m = re.search(r'(?m)^\s*def\s+\w*'+re.escape(which)+r'\w*\s*\(', t)
        if m:
            start = m.start()
    if start is None:
        print(f"[WARN] cannot find handler for {which}")
        return

    # determine handler region
    tail = t[start:]
    m_end = re.search(r'(?m)^(?:@|def)\s+', tail[1:])
    end = start + (m_end.start()+1 if m_end else len(t))
    region = t[start:end]

    # wrap ALL return lines in this region (skip already-wrapped)
    out_lines = []
    for line in region.splitlines(True):
        mret = re.match(r'^(\s*)return\s+(.+?)\s*$', line)
        if not mret:
            out_lines.append(line); continue
        indent, expr = mret.group(1), mret.group(2)
        if "__vsp_ret" in line or post_fn in line:
            out_lines.append(line); continue

        repl = (
            f"{indent}__vsp_ret = ({expr})\n"
            f"{indent}return {post_fn}(__vsp_ret, locals())\n"
        )
        out_lines.append(repl)

    new_region = "".join(out_lines)
    t = t[:start] + new_region + t[end:]
    print(f"[OK] wrapped returns for {which} -> {post_fn}")

wrap_handler("run_status_v1", "_vsp__postprocess_status_v1")
wrap_handler("run_status_v2", "_vsp__postprocess_status_v2")

p.write_text(t, encoding="utf-8")
print("[OK] wrote", p)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"
