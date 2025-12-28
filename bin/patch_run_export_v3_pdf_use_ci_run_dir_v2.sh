#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_use_ci_${TS}"
echo "[BACKUP] $F.bak_exportpdf_use_ci_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_EXPORT_PDF_RESOLVE_RUN_DIR_FROM_STATUSV2_V2 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Insert helper function once near top-level (after imports area best-effort)
ins = """
{TAG}
def _vsp_resolve_ci_run_dir_from_status_v2_v2(rid: str):
    \"\"\"Commercial: resolve run_dir using same contract as UI (run_status_v2).\"\"\"
    try:
        # local call: avoid requests dependency by importing urllib
        import json as _json
        from urllib.request import urlopen as _urlopen
        u = "http://127.0.0.1:8910/api/vsp/run_status_v2/" + str(rid)
        with _urlopen(u, timeout=2) as r:
            data = r.read().decode("utf-8", "ignore")
        d = _json.loads(data)
        ci = d.get("ci_run_dir") or d.get("ci") or ""
        if ci and isinstance(ci, str):
            return ci
    except Exception:
        return None
    return None
""".replace("{TAG}", TAG)

# put helper after first "import" block
if TAG not in t:
    t = re.sub(r"(\nimport[^\n]*\n)", r"\1\n"+ins+"\n", t, count=1)

# Now patch the early-return block to use ci_run_dir resolver if run_dir missing
pat = re.compile(r"(# === VSP_RUN_EXPORT_V3_PDF_EARLY_RETURN_V1 ===.*?run_dir\s*=\s*None.*?\n)", re.S)
m = pat.search(t)
if not m:
    print("[ERR] cannot find early-return block V1 to enhance")
    raise SystemExit(1)

block = m.group(1)
if "_vsp_resolve_ci_run_dir_from_status_v2_v2" in block:
    print("[OK] early-return already enhanced")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

inject = """
        # Commercial: if still unresolved, use status_v2 contract to get ci_run_dir
        if not run_dir:
            try:
                run_dir = _vsp_resolve_ci_run_dir_from_status_v2_v2(rid_norm) or _vsp_resolve_ci_run_dir_from_status_v2_v2(rid_norm2)
            except Exception:
                pass
"""

# Insert after initial candidate loop, right before files collection
# find "run_dir = None" then after cand scan loop
block2 = re.sub(r"(for\s+c\s+in\s+cands:.*?break\s*\n\s*except Exception:\s*\n\s*pass\s*\n)", r"\1"+inject, block, count=1, flags=re.S)
t2 = t.replace(block, block2, 1)

p.write_text(t2, encoding="utf-8")
print("[OK] patched: export pdf run_dir resolves from run_status_v2 ci_run_dir")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"
fuser -k 8910/tcp 2>/dev/null || true
[ -x bin/restart_8910_gunicorn_commercial_v5.sh ] && bin/restart_8910_gunicorn_commercial_v5.sh || true
echo "[DONE] patch_run_export_v3_pdf_use_ci_run_dir_v2"
