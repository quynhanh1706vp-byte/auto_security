#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tail_kics_${TS}"
echo "[BACKUP] $F.bak_tail_kics_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# helper tail reader (append near top: after imports)
ins_helper = r'''
# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1 ===
def _vsp_tail_file(path: str, max_bytes: int = 4096) -> str:
    try:
        fp = Path(path)
        if not fp.exists():
            return ""
        data = fp.read_bytes()
        if len(data) > max_bytes:
            data = data[-max_bytes:]
        try:
            return data.decode("utf-8", errors="ignore")
        except Exception:
            return str(data)[0:max_bytes]
    except Exception:
        return ""
# === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V1 ===
'''

# insert helper after first "from flask" import block or after initial imports
m = re.search(r"^(from flask[^\n]*\n(?:from flask[^\n]*\n)*)", t, flags=re.M)
if m:
    idx = m.end()
    t = t[:idx] + "\n" + ins_helper + "\n" + t[idx:]
    print("[OK] inserted helper after flask imports")
else:
    t = ins_helper + "\n" + t
    print("[WARN] flask import block not found; prepended helper")

# patch in run_status_v1 response: before jsonify/return, override tail if stage is KICS
# (best-effort: locate a block that sets stage_name + ci_run_dir + tail)
# We'll inject a small snippet at the first occurrence of 'stage_name' assignment near response build.
snippet = r'''
    # Prefer tool log tail for "commercial" liveness (KICS heartbeat etc.)
    try:
        _sn = (stage_name or "").lower()
        if "kics" in _sn and ci_run_dir:
            _klog = str(Path(ci_run_dir) / "kics" / "kics.log")
            _ktail = _vsp_tail_file(_klog, 4096)
            if _ktail:
                tail = _ktail
    except Exception:
        pass
'''

# insert snippet near where payload dict is assembled; try multiple anchors
anchors = [
    r"\n\s*payload\s*=\s*\{",
    r"\n\s*resp\s*=\s*\{",
    r"\n\s*return\s+jsonify\("
]
inserted = False
for a in anchors:
    m2 = re.search(a, t)
    if m2:
        t = t[:m2.start()] + snippet + t[m2.start():]
        inserted = True
        print("[OK] inserted tail-override snippet before response build")
        break
if not inserted:
    # fallback: append at end (still safe)
    t += "\n" + snippet + "\n"
    print("[WARN] could not find response anchor; appended snippet at end (may not be effective)")

p.write_text(t, encoding="utf-8")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
