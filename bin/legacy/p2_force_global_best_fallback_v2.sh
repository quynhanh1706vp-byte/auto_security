#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

cp -f "$APP" "${APP}.bak_globalbest_${TS}"
echo "[OK] backup: ${APP}.bak_globalbest_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

tag_b="# ===== VSP_GLOBAL_BEST_FALLBACK_V2 ====="
tag_e="# ===== /VSP_GLOBAL_BEST_FALLBACK_V2 ====="
if tag_b in s and tag_e in s:
    print("[OK] GLOBAL_BEST_FALLBACK_V2 already present")
else:
    patch = r"""

# ===== VSP_GLOBAL_BEST_FALLBACK_V2 =====
# Commercial: if RID dataset is tiny, fallback to GLOBAL_BEST (largest findings_unified*.json across SECURITY_BUNDLE).
try:
    import os, glob, time
except Exception:
    os = None; glob = None; time = None

_VSP_MIN_RID_BYTES_FOR_DEMO = 50000   # 50KB
_VSP_GLOBAL_BEST_CACHE = {"ts": 0.0, "path": None, "size": 0}

def _vsp_pick_global_best_path():
    if os is None or glob is None or time is None:
        return None
    now = time.time()
    if _VSP_GLOBAL_BEST_CACHE["path"] and (now - _VSP_GLOBAL_BEST_CACHE["ts"] < 30.0):
        return _VSP_GLOBAL_BEST_CACHE["path"]

    roots = [
        "/home/test/Data/SECURITY_BUNDLE/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/findings_unified_commercial.json",
    ]

    pats = [
        "/home/test/Data/SECURITY_BUNDLE/out/**/reports/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out/**/unified/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out/**/report/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/**/reports/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/**/unified/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/**/report/findings_unified.json",
        "/home/test/Data/SECURITY_BUNDLE/out_ci/**/findings_unified.json",
    ]

    best_path = None
    best_size = -1

    for f in roots:
        if os.path.isfile(f):
            try:
                sz = os.path.getsize(f)
            except Exception:
                sz = 0
            if sz > best_size:
                best_size = sz
                best_path = f

    for pat in pats:
        for f in glob.glob(pat, recursive=True):
            if not os.path.isfile(f):
                continue
            try:
                sz = os.path.getsize(f)
            except Exception:
                sz = 0
            if sz > best_size:
                best_size = sz
                best_path = f

    _VSP_GLOBAL_BEST_CACHE.update({"ts": now, "path": best_path, "size": best_size if best_size >= 0 else 0})
    return best_path

# OVERRIDE: strongest definition wins (placed near end of file)
def _vsp_find_findings_file(rid: str):
    if os is None:
        return None

    # 1) First, try RID-local candidates (same as before)
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

    rid_best = None
    rid_best_sz = -1
    if rid:
        for b in bases:
            for r in rels:
                f = os.path.join(b, r)
                if os.path.isfile(f):
                    try:
                        sz = os.path.getsize(f)
                    except Exception:
                        sz = 0
                    if sz > rid_best_sz:
                        rid_best_sz = sz
                        rid_best = f

    # 2) If RID file is tiny => fallback to GLOBAL_BEST for demo
    gbest = _vsp_pick_global_best_path()
    if gbest and os.path.isfile(gbest):
        try:
            gsz = os.path.getsize(gbest)
        except Exception:
            gsz = 0
        if (rid_best is None) or (rid_best_sz < _VSP_MIN_RID_BYTES_FOR_DEMO and gsz > 0):
            return gbest

    # 3) Otherwise keep RID best
    return rid_best
# ===== /VSP_GLOBAL_BEST_FALLBACK_V2 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended GLOBAL_BEST_FALLBACK_V2 (override _vsp_find_findings_file)")
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
