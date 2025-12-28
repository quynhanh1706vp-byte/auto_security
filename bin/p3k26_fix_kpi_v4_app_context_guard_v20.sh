#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
FILES=(wsgi_vsp_ui_gateway.py vsp_demo_app.py)

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3

python3 - <<'PY'
from pathlib import Path
import re, time

tag="P3K26_KPI_V4_CONTEXT_GUARD_V20"
targets=["wsgi_vsp_ui_gateway.py","vsp_demo_app.py"]

for fn in targets:
    p=Path(fn)
    if not p.exists(): 
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    if tag in s:
        print("[OK] already patched:", fn)
        continue

    if "VSP_KPI_V4" not in s:
        print("[SKIP] no VSP_KPI_V4 marker:", fn)
        continue

    # heuristic: wrap any direct call that looks like "kpi_v4_mount(...)" / "mount_kpi_v4(...)" etc.
    # We do a conservative patch: when we see "VSP_KPI_V4" line, we inject a safe guard block right above it
    lines=s.splitlines(True)
    out=[]
    patched=False
    for i,ln in enumerate(lines):
        if (not patched) and ("VSP_KPI_V4" in ln) and (not ln.lstrip().startswith("#")):
            out.append(f"# {tag}: guard KPI V4 mount inside app.app_context if possible\n")
            out.append("try:\n")
            out.append("    _a = globals().get('app') or globals().get('application')\n")
            out.append("    if _a is not None and hasattr(_a, 'app_context'):\n")
            out.append("        _ctx = _a.app_context()\n")
            out.append("        _ctx.push()\n")
            out.append("        _VSP_P3K26_CTX_PUSHED = True\n")
            out.append("    else:\n")
            out.append("        _VSP_P3K26_CTX_PUSHED = False\n")
            out.append("except Exception:\n")
            out.append("    _VSP_P3K26_CTX_PUSHED = False\n")
            out.append(ln)
            out.append("try:\n")
            out.append("    if globals().get('_VSP_P3K26_CTX_PUSHED'):\n")
            out.append("        _ctx.pop()\n")
            out.append("except Exception:\n")
            out.append("    pass\n")
            patched=True
        else:
            out.append(ln)

    if patched:
        bak = f"{fn}.bak_kpiv4_ctx_{int(time.time())}"
        Path(bak).write_text(s, encoding="utf-8")
        p.write_text("".join(out), encoding="utf-8")
        print("[OK] patched:", fn, "backup:", bak)
    else:
        print("[WARN] could not patch safely:", fn)
PY

sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
