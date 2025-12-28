#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_status_contract_${TS}" && echo "[BACKUP] $F.bak_status_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK_BEGIN="# === VSP_RUN_STATUS_V2_CONTRACT_P1_V1_BEGIN ==="
MARK_END  ="# === VSP_RUN_STATUS_V2_CONTRACT_P1_V1_END ==="

helper = r'''
{MARK_BEGIN}
import os, json, glob

def _vsp_read_json(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def _vsp_find_run_dir(rid: str):
    """Best-effort resolve run dir for VSP_CI_* RID."""
    if not rid:
        return None
    # candidate roots (add more if needed)
    roots = [
        os.environ.get("VSP_OUT_CI_ROOT", ""),
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    roots = [r for r in roots if r and os.path.isdir(r)]
    for r in roots:
        cand = os.path.join(r, rid)
        if os.path.isdir(cand):
            return cand
    # fallback glob
    for r in roots:
        hits = glob.glob(os.path.join(r, rid + "*"))
        for h in hits:
            if os.path.isdir(h):
                return h
    return None

def _vsp_findings_total(run_dir: str):
    if not run_dir:
        return None
    # prefer unified file if exists
    for fn in ("findings_unified.json","reports/findings_unified.json","findings_unified.sarif.json"):
        fp=os.path.join(run_dir, fn)
        if os.path.isfile(fp):
            j=_vsp_read_json(fp)
            if isinstance(j, dict):
                if isinstance(j.get("total"), int):
                    return j["total"]
                items=j.get("items")
                if isinstance(items, list):
                    return len(items)
    # fallback: any findings json
    fp=os.path.join(run_dir,"summary_unified.json")
    j=_vsp_read_json(fp) if os.path.isfile(fp) else None
    if isinstance(j, dict):
        t=j.get("total") or j.get("total_findings")
        if isinstance(t, int):
            return t
    return None

def _vsp_degraded_info(run_dir: str):
    """Best-effort degraded detection from runner.log (commercial degrade markers)."""
    if not run_dir:
        return (None, None)
    logp=os.path.join(run_dir,"runner.log")
    if not os.path.isfile(logp):
        # try tool logs
        for alt in ("kics/kics.log","codeql/codeql.log","trivy/trivy.log"):
            if os.path.isfile(os.path.join(run_dir,alt)):
                logp=os.path.join(run_dir,alt); break
        else:
            return (None, None)

    try:
        txt=Path(logp).read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return (None, None)

    tools = ["BANDIT","SEMGREP","GITLEAKS","KICS","TRIVY","SYFT","GRYPE","CODEQL"]
    degraded=set()
    for t in tools:
        # strong markers we already use in scripts
        pats = [
            fr"VSP_{t}_TIMEOUT_DEGRADE",
            fr"\[{t}\].*DEGRADED",
            fr"{t}.*timeout.*degrad",
            fr"{t}.*missing.*degrad",
        ]
        for pat in pats:
            if re.search(pat, txt, flags=re.I):
                degraded.add(t)
                break
    n=len(degraded)
    return (n, n>0)

{MARK_END}
'''.replace("{MARK_BEGIN}", MARK_BEGIN).replace("{MARK_END}", MARK_END)

# remove old helper block if any, then inject
if MARK_BEGIN in s and MARK_END in s:
    s=re.sub(re.escape(MARK_BEGIN)+r".*?"+re.escape(MARK_END), helper, s, flags=re.S)
else:
    # insert helper after imports (best effort)
    m=re.search(r"(?m)^(import\s+[^\n]+\n)+", s)
    if m:
        insert_at=m.end()
        s=s[:insert_at] + "\n" + helper + "\n" + s[insert_at:]
    else:
        s=helper + "\n" + s

# patch the run_status_v2 route: wrap its returned json dict (best effort)
# We handle multiple styles:
# - @app.route("/api/vsp/run_status_v2/<rid>") def ...: return jsonify(obj)
# - blueprint route similarly
route_pat = r'@[^\\n]*run_status_v2[^\\n]*\\n\\s*def\\s+([a-zA-Z0-9_]+)\\s*\\(\\s*rid\\s*\\)'
m=re.search(route_pat, s)
if not m:
    # if no route, add new route at end (safe if not already defined)
    add = r'''
@app.get("/api/vsp/run_status_v2/<rid>")
def api_vsp_run_status_v2_contract_p1_v1(rid):
    # try to call existing v1/v2 provider if available, else return contract only
    base = {}
    try:
        # attempt reuse: if there is an internal helper, keep as-is
        pass
    except Exception:
        base = {}
    run_dir = base.get("ci_run_dir") or base.get("ci") or _vsp_find_run_dir(rid)
    if run_dir:
        base["ci_run_dir"] = run_dir
    base["run_id"] = rid

    total = _vsp_findings_total(run_dir) if run_dir else None
    if isinstance(total, int):
        base["total_findings"] = total
        base["has_findings"] = True if total > 0 else False

    dn, da = _vsp_degraded_info(run_dir) if run_dir else (None, None)
    if isinstance(dn, int):
        base["degraded_n"] = dn
    if isinstance(da, bool):
        base["degraded_any"] = da

    base.setdefault("ok", True)
    base.setdefault("status", base.get("status") or "UNKNOWN")
    return jsonify(base)
'''
    s = s.rstrip() + "\n\n" + add + "\n"
else:
    fn_name=m.group(1)
    # inject enrichment just before any "return jsonify(...)" inside that function
    # Best-effort: locate function block by next "def " at same indentation
    start=m.start()
    # find function header end
    hdr = re.search(rf'(?m)^def\s+{re.escape(fn_name)}\s*\(\s*rid\s*\)\s*:\s*$', s[start:])
    if not hdr:
        # alternate signature (rid, ...)
        hdr = re.search(rf'(?m)^def\s+{re.escape(fn_name)}\s*\(.*rid.*\)\s*:\s*$', s[start:])
    if hdr:
        fstart = start + hdr.start()
        # function block end: next line that starts with "def " at column 0
        nxt = re.search(r'(?m)^\s*def\s+[a-zA-Z0-9_]+\s*\(', s[fstart+1:])
        fend = (fstart+1+nxt.start()) if nxt else len(s)
        fblk = s[fstart:fend]

        # patch only if not already enriched
        if "VSP_STATUS_CONTRACT_ENRICH_P1_V1" not in fblk:
            # replace first "return jsonify(X)" with enrichment wrapper
            def repl(match):
                obj = match.group(1).strip()
                ins = r'''
    # VSP_STATUS_CONTRACT_ENRICH_P1_V1
    try:
        _base = {obj}
        if not isinstance(_base, dict):
            _base = {{"data": _base}}
    except Exception:
        _base = {{}}
    _base["run_id"] = rid
    _run_dir = _base.get("ci_run_dir") or _base.get("ci") or _vsp_find_run_dir(rid)
    if _run_dir:
        _base["ci_run_dir"] = _run_dir
        _t = _vsp_findings_total(_run_dir)
        if isinstance(_t, int):
            _base["total_findings"] = _t
            _base["has_findings"] = True if _t > 0 else False
        _dn, _da = _vsp_degraded_info(_run_dir)
        if isinstance(_dn, int):
            _base["degraded_n"] = _dn
        if isinstance(_da, bool):
            _base["degraded_any"] = _da
    return jsonify(_base)
'''.replace("{obj}", obj)
                return ins
            fblk2 = re.sub(r'(?m)^\s*return\s+jsonify\s*\(\s*(.+?)\s*\)\s*$', repl, fblk, count=1)
            s = s[:fstart] + fblk2 + s[fend:]

p.write_text(s, encoding="utf-8")
print("[OK] patched vsp_demo_app.py for run_status_v2 contract P1")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile OK"

echo
echo "[NEXT] restart UI gunicorn (8910) then re-check run_status_v2 fields."
