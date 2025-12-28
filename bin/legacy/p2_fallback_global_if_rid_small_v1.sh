#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

cp -f "$APP" "${APP}.bak_globalfb_${TS}"
echo "[OK] backup: ${APP}.bak_globalfb_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

tag_b="# ===== VSP_GLOBAL_FALLBACK_IF_SMALL_V1 ====="
tag_e="# ===== /VSP_GLOBAL_FALLBACK_IF_SMALL_V1 ====="
if tag_b in s and tag_e in s:
    print("[OK] global fallback already present")
else:
    patch=r"""

# ===== VSP_GLOBAL_FALLBACK_IF_SMALL_V1 =====
# If RID file is tiny/empty, fallback to global findings_unified.json for commercial demo.
try:
    import os
except Exception:
    os = None

_VSP_GLOBAL_FINDINGS_PATH = "/home/test/Data/SECURITY_BUNDLE/findings_unified.json"
_VSP_MIN_BYTES_FOR_RID = 50000   # 50KB (tune if needed)

def _vsp_find_findings_file(rid: str):
    if os is None:
        return None
    if not rid:
        return _VSP_GLOBAL_FINDINGS_PATH if os.path.isfile(_VSP_GLOBAL_FINDINGS_PATH) else None

    bases = [
        f"/home/test/Data/SECURITY_BUNDLE/out_ci/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/out/{rid}",
        f"/home/test/Data/SECURITY_BUNDLE/ui/out_ci/{rid}",
    ]
    rels = [
        "reports/findings_unified_commercial.json",
        "report/findings_unified_commercial.json",
        "findings_unified_commercial.json",
        "unified/findings_unified.json",
        "reports/findings_unified.json",
        "report/findings_unified.json",
        "findings_unified.json",
    ]

    cand=[]
    for b in bases:
        for r in rels:
            f=os.path.join(b,r)
            if os.path.isfile(f):
                try: sz=os.path.getsize(f)
                except Exception: sz=0
                cand.append((sz,f))

    best = None
    if cand:
        cand.sort(key=lambda x: x[0], reverse=True)
        best = cand[0]  # (size, path)

    # fallback condition: rid file tiny/empty -> use global if it exists and is bigger
    if os.path.isfile(_VSP_GLOBAL_FINDINGS_PATH):
        try: gsz=os.path.getsize(_VSP_GLOBAL_FINDINGS_PATH)
        except Exception: gsz=0
        if (best is None) or (best[0] < _VSP_MIN_BYTES_FOR_RID and gsz > best[0]):
            return _VSP_GLOBAL_FINDINGS_PATH

    return best[1] if best else None
# ===== /VSP_GLOBAL_FALLBACK_IF_SMALL_V1 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended global fallback V1")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.7
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

curl -fsS "$BASE/api/vsp/findings_page_v3?rid=$RID&limit=10&offset=0" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("from_path=",j.get("from_path"),"total_findings=",j.get("total_findings"),"items_len=",len(j.get("items") or []))'

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"
