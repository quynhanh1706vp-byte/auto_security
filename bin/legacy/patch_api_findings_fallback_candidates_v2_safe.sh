#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_findfallback_v2_${TS}"
echo "[BACKUP] $F.bak_findfallback_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8")

MARK = "VSP_FINDINGS_FALLBACK_V2_SAFE"
if MARK in s:
    print("[OK] already patched, skip")
    raise SystemExit(0)

helper = r'''
# === %s ===
def _vsp_guess_run_roots():
    import os
    roots = []
    # env override (colon separated)
    env = os.environ.get("VSP_RUNS_ROOTS","").strip()
    if env:
        for r in env.split(":"):
            r=r.strip()
            if r: roots.append(r)

    # common relative roots
    roots += ["out_ci", "out", "./out_ci", "./out"]

    # common absolute roots (only used if exist)
    roots += [
        "/home/test/Data/SECURITY-10-10-v4/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
    ]

    # de-dup keep order
    out=[]
    seen=set()
    for r in roots:
        if r in seen: continue
        seen.add(r)
        out.append(r)
    return out

def _vsp_pick_findings_fp(run_dir: str):
    import os
    if not run_dir:
        return None
    cands = [
        os.path.join(run_dir, "findings_unified.json"),
        os.path.join(run_dir, "reports", "findings_unified.json"),
        os.path.join(run_dir, "artifacts", "findings_unified.json"),
        os.path.join(run_dir, "findings", "findings_unified.json"),
    ]
    for fp in cands:
        try:
            if os.path.isfile(fp) and os.path.getsize(fp) > 2:
                return fp
        except Exception:
            pass
    return None

def _vsp_resolve_run_dir_from_rid(rid: str):
    import os
    if not rid:
        return None
    # if rid is already a dir path
    if os.path.isdir(rid):
        return rid
    # if rid looks like a file path (e.g., .../findings_unified.json)
    if os.path.isfile(rid):
        return os.path.dirname(rid)

    # otherwise try to find a run dir under known roots
    for root in _vsp_guess_run_roots():
        try:
            root_abs = root
            if not os.path.isabs(root_abs):
                root_abs = os.path.abspath(root_abs)
            cand = os.path.join(root_abs, rid)
            if os.path.isdir(cand):
                return cand
        except Exception:
            pass
    return None
# === /%s ===
''' % (MARK, MARK)

# Insert helper BEFORE the first findings_preview route/def (top-level)
m = re.search(r'(?m)^\s*@app\.route\(\s*[\'"]\/api\/vsp\/findings_preview', s)
if not m:
    m = re.search(r'(?m)^\s*def\s+api_vsp_findings_preview', s)

if not m:
    # fallback: insert near top after imports (after last import/from line block)
    imp_end = 0
    for mm in re.finditer(r'(?m)^(?:from\s+\S+\s+import\s+.*|import\s+.*)\s*$', s):
        imp_end = mm.end()
    ins = imp_end if imp_end else 0
    s2 = s[:ins] + "\n" + helper + "\n" + s[ins:]
else:
    ins = m.start()
    s2 = s[:ins] + helper + "\n" + s[ins:]

# Now patch each findings endpoint: after it computes run_dir, ensure fp uses fallback
# Strategy: inject a small block after first occurrence of a line containing "findings_unified.json"
def patch_endpoint(block: str) -> str:
    if "VSP_FINDINGS_FALLBACK_APPLIED_V2" in block:
        return block
    # add fallback after any "fp = os.path.join(..., 'findings_unified.json')" line
    block2 = re.sub(
        r'(?m)^(?P<indent>\s*)fp\s*=\s*.*findings_unified\.json.*$',
        r'\g<indent>\g<0>\n'
        r'\g<indent># VSP_FINDINGS_FALLBACK_APPLIED_V2\n'
        r'\g<indent>if (not fp) or (not _os.path.isfile(fp)):\n'
        r'\g<indent>    _rd = locals().get("run_dir") or locals().get("RUN_DIR")\n'
        r'\g<indent>    _picked = _vsp_pick_findings_fp(_rd) if _rd else None\n'
        r'\g<indent>    if _picked: fp = _picked\n',
        block,
        count=1
    )
    return block2

# patch functions by regex capture (best-effort, safe if not matched)
for fn in ["api_vsp_findings_preview_v1", "api_vsp_findings_preview_v2"]:
    pat = rf'(?s)(def\s+{fn}\b.*?\n)(?=def\s+|@app\.route\(|\Z)'
    mm = re.search(pat, s2)
    if mm:
        whole = mm.group(0)
        s2 = s2.replace(whole, patch_endpoint(whole))

p.write_text(s2, encoding="utf-8")
print("[OK] patched helper + best-effort endpoint fallback")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart 8910
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
echo "[DONE]"
