#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guessci_v33_rewrite_v4_${TS}"
echo "[BACKUP] $F.bak_guessci_v33_rewrite_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

FN = "_vsp_guess_ci_run_dir_from_rid_v33"
TAG = "# === VSP_GUESS_CI_RUN_DIR_V33_REWRITE_CLEAN_V4 ==="

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# find def line
def_re = re.compile(r'^([ \t]*)def\s+' + re.escape(FN) + r'\s*\(.*\)\s*(?:->\s*[^:]+)?\s*:\s*$')
i0 = None
indent0 = ""
for i,l in enumerate(lines):
    m = def_re.match(l)
    if m:
        i0 = i
        indent0 = m.group(1)
        break
if i0 is None:
    raise SystemExit(f"[ERR] cannot find def {FN}()")

# find block end by dedent
i1 = None
for j in range(i0+1, len(lines)):
    lj = lines[j]
    if lj.strip() == "":
        continue
    if not (lj.startswith(indent0) and len(lj) > len(indent0) and lj[len(indent0)] in (" ", "\t")):
        i1 = j
        break
if i1 is None:
    i1 = len(lines)

old = "".join(lines[i0:i1])
if TAG in old:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

new = f"""{indent0}def {FN}(rid_norm):
{indent0}    {TAG}
{indent0}    \"\"\"Return absolute CI run dir for a RID (RUN_* / VSP_CI_* / VSP_UIREQ_*).
{indent0}    - If RID is UIREQ: read persisted state under ui/out_ci/uireq_v1/<RID>.json
{indent0}    - Else: find */out_ci/<RID> under /home/test/Data with shallow globs
{indent0}    \"\"\"
{indent0}    try:
{indent0}        import json
{indent0}        from pathlib import Path
{indent0}        rn = str(rid_norm or '').strip()
{indent0}        if not rn:
{indent0}            return None
{indent0}        if rn.startswith("RUN_"):
{indent0}            rn = rn[4:].strip()

{indent0}        # UIREQ -> read persisted state (if exists)
{indent0}        if rn.startswith("VSP_UIREQ_"):
{indent0}            st = Path("/home/test/Data/SECURITY_BUNDLE/ui/ui/out_ci/uireq_v1") / (rn + ".json")
{indent0}            if st.is_file():
{indent0}                try:
{indent0}                    obj = json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{indent0}                    if isinstance(obj, dict):
{indent0}                        ci = (obj.get("ci_run_dir") or obj.get("ci_dir") or obj.get("ci") or "").strip()
{indent0}                        if ci and Path(ci).is_dir():
{indent0}                            return str(Path(ci))
{indent0}                except Exception:
{indent0}                    pass

{indent0}        base = Path("/home/test/Data")

{indent0}        # very fast common hit: /home/test/Data/*/out_ci/<rn>
{indent0}        try:
{indent0}            for c in base.glob("*/out_ci/" + rn):
{indent0}                if c.is_dir():
{indent0}                    return str(c)
{indent0}        except Exception:
{indent0}            pass

{indent0}        # shallow fallbacks (no ** recursion)
{indent0}        pats = (
{indent0}            "*/*/out_ci/" + rn,
{indent0}            "*/*/*/out_ci/" + rn,
{indent0}            "*/*/*/*/out_ci/" + rn,
{indent0}        )
{indent0}        for pat in pats:
{indent0}            try:
{indent0}                for c in base.glob(pat):
{indent0}                    if c.is_dir():
{indent0}                        return str(c)
{indent0}            except Exception:
{indent0}                continue

{indent0}        return None
{indent0}    except Exception:
{indent0}        return None
"""

lines2 = lines[:i0] + [new] + lines[i1:]
p.write_text("".join(lines2), encoding="utf-8")
print("[OK] rewrote function:", FN, "lines", i0, "..", i1)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should now include ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
