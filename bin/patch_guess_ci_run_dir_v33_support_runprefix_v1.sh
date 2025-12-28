#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_guessci_v33_${TS}"
echo "[BACKUP] $F.bak_guessci_v33_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_GUESS_CI_RUN_DIR_V33_SUPPORT_RUNPREFIX_V1 ==="
if TAG in t:
    print("[OK] tag already present, skip")
    raise SystemExit(0)

m = re.search(r'(?m)^def\s+_vsp_guess_ci_run_dir_from_rid_v33\s*\(\s*([^\)]*)\)\s*:', t)
if not m:
    print("[ERR] cannot find def _vsp_guess_ci_run_dir_from_rid_v33(...)")
    raise SystemExit(2)

start = m.start()

# find end of function block (next top-level def)
m2 = re.search(r'(?m)^\s*def\s+', t[m.end():])
if m2:
    end = m.end() + m2.start()
else:
    end = len(t)

new_fn = f'''def _vsp_guess_ci_run_dir_from_rid_v33(rid):
    {TAG}
    """
    Robustly map RID -> CI run dir.
    Supports:
      - RUN_VSP_CI_YYYYmmdd_HHMMSS  (strip RUN_)
      - VSP_CI_YYYYmmdd_HHMMSS
      - VSP_UIREQ_* (optional: read uireq_v1 state)
    Strategy:
      1) normalize rid (strip RUN_)
      2) try known base(s)
      3) fast glob under /home/test/Data for */out_ci/<rid>
    """
    try:
        rid = (rid or "").strip()
        if not rid:
            return None

        rid_norm = rid
        if rid_norm.startswith("RUN_"):
            rid_norm = rid_norm[4:].strip()

        # 0) UIREQ state (optional)
        if rid_norm.startswith("VSP_UIREQ_"):
            st = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1") / f"{{rid_norm}}.json"
            if st.exists():
                try:
                    import json as _json
                    j = _json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{{}}")
                    ci = (j.get("ci_run_dir") or "").strip()
                    if ci and Path(ci).is_dir():
                        return ci
                except Exception:
                    pass

        # 1) known base (your current CI runs)
        known = Path("/home/test/Data/SECURITY-10-10-v4/out_ci") / rid_norm
        if known.is_dir():
            return str(known)

        # 2) fast glob in /home/test/Data (1-level)
        base = Path("/home/test/Data")
        patterns = [
            f"*/out_ci/{{rid_norm}}",
            f"SECURITY*/out_ci/{{rid_norm}}",
        ]
        for pat in patterns:
            for cand in base.glob(pat):
                if cand.is_dir():
                    return str(cand)

        return None
    except Exception:
        return None
'''

t2 = t[:start] + new_fn + "\n\n" + t[end:]
p.write_text(t2, encoding="utf-8")
print("[OK] patched _vsp_guess_ci_run_dir_from_rid_v33")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-gateway
sudo systemctl is-active vsp-ui-gateway && echo SVC_OK

echo "== [VERIFY] run_status_v2 should have ci_run_dir + kics_* =="
curl -sS "http://127.0.0.1:8910/api/vsp/run_status_v2/RUN_VSP_CI_20251214_224900" \
 | jq '{ci_run_dir,kics_verdict,kics_total,kics_counts}'
