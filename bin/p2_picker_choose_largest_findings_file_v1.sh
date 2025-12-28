#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

cp -f "$APP" "${APP}.bak_picklargest_${TS}"
echo "[OK] backup: ${APP}.bak_picklargest_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

tag_b="# ===== VSP_PICK_LARGEST_FINDINGS_FILE_V1 ====="
tag_e="# ===== /VSP_PICK_LARGEST_FINDINGS_FILE_V1 ====="

if tag_b in s and tag_e in s:
    print("[OK] pick-largest already present")
else:
    patch=r"""

# ===== VSP_PICK_LARGEST_FINDINGS_FILE_V1 =====
# Override only the file picker to avoid empty placeholder files.
try:
    import os
except Exception:
    os = None

def _vsp_find_findings_file(rid: str):
    if os is None:
        return None
    if not rid:
        return None

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
                try:
                    sz=os.path.getsize(f)
                except Exception:
                    sz=0
                cand.append((sz,f))

    if not cand:
        return None

    cand.sort(key=lambda x: x[0], reverse=True)
    # prefer non-tiny file
    for sz,f in cand:
        if sz >= 200:   # ignore tiny placeholders
            return f
    # fallback: return largest anyway
    return cand[0][1]
# ===== /VSP_PICK_LARGEST_FINDINGS_FILE_V1 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended pick-largest override")
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
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("from_path=",j.get("from_path"),"total_findings=",j.get("total_findings"),"items_len=",len(j.get("items") or []),"sev=",j.get("sev"))'

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"
