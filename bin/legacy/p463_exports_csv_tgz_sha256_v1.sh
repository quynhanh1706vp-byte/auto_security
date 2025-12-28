#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P463_EXPORTS_CSV_TGZ_SHA256_V1"
if MARK in s:
    print("[OK] already patched P463")
    sys.exit(0)

block = r'''
# --- VSP_P463_EXPORTS_CSV_TGZ_SHA256_V1 ---
def _vsp_p463_candidate_roots():
    """
    Try to find run directories by RID without assuming one fixed layout.
    """
    from pathlib import Path
    import os
    roots = []

    # env overrides (optional)
    for k in ("VSP_RUNS_ROOT", "SECURITY_BUNDLE_OUT", "SECURITY_BUNDLE_OUT_CI"):
        v = os.getenv(k, "").strip()
        if v:
            roots.append(Path(v))

    # known defaults
    roots += [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE"),
    ]

    # dedupe + keep existing dirs only
    seen=set()
    out=[]
    for r in roots:
        try:
            r = r.resolve()
        except Exception:
            pass
        if str(r) in seen:
            continue
        seen.add(str(r))
        if r.exists():
            out.append(r)
    return out

def _vsp_p463_find_run_dir(rid: str):
    from pathlib import Path
    if not rid:
        return None
    rid = str(rid).strip()
    for base in _vsp_p463_candidate_roots():
        # direct: base/rid
        p = base / rid
        if p.is_dir():
            return p

        # common nesting: base/{out,out_ci,runs}/rid
        for sub in ("out_ci", "out", "runs", "ui/out_ci", "ui/out"):
            q = base / sub / rid
            if q.is_dir():
                return q

        # one-level search: base/*/rid
        try:
            for d in base.iterdir():
                if d.is_dir():
                    q = d / rid
                    if q.is_dir():
                        return q
        except Exception:
            pass
    return None

def _vsp_p463_latest_rid():
    """
    Best-effort: pick newest RID-like folder (VSP_CI_*) from known roots.
    """
    import re
    best=None
    for base in _vsp_p463_candidate_roots():
        try:
            for d in base.iterdir():
                if not d.is_dir():
                    continue
                name = d.name
                if name.startswith("VSP_CI_"):
                    if (best is None) or (name > best):
                        best = name
        except Exception:
            pass
    return best

def _vsp_p463_pick_csv(run_dir):
    from pathlib import Path
    cands = [
        run_dir / "reports" / "findings_unified.csv",
        run_dir / "report"  / "findings_unified.csv",
        run_dir / "reports" / "findings_unified.csv",
        run_dir / "findings_unified.csv",
    ]
    for f in cands:
        if f.is_file() and f.stat().st_size > 0:
            return f
    return None

def _vsp_p463_exports_cache_dir():
    from pathlib import Path
    root = Path(__file__).resolve().parent
    d = root / "out_ci" / "exports_cache"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp_p463_build_tgz_cached(run_dir, rid: str):
    """
    Build a deterministic-ish tgz containing key evidence files.
    Cache under ui/out_ci/exports_cache/export_<rid>.tgz
    """
    import tarfile, time
    from pathlib import Path

    rid = str(rid).strip() or "RID_UNKNOWN"
    cache = _vsp_p463_exports_cache_dir() / f"export_{rid}.tgz"
    if cache.is_file() and cache.stat().st_size > 0:
        return cache

    include = [
        "SUMMARY.txt",
        "run_manifest.json",
        "run_evidence_index.json",
        "verdict_4t.json",
        "run_gate.json",
        "reports/run_gate_summary.json",
        "reports/findings_unified.json",
        "reports/findings_unified.csv",
        "reports/findings_unified.sarif",
        "findings_unified.json",
        "findings_unified.csv",
        "findings_unified.sarif",
        "reports",   # whole folder if exists
    ]

    # build archive
    with tarfile.open(cache, "w:gz") as tf:
        for rel in include:
            p = (run_dir / rel)
            if not p.exists():
                continue
            # avoid huge / unsafe stuff: follow only within run_dir
            try:
                rp = p.resolve()
                if not str(rp).startswith(str(run_dir.resolve())):
                    continue
            except Exception:
                pass

            if p.is_dir():
                # add dir tree
                for sub in p.rglob("*"):
                    if sub.is_file():
                        arc = f"{rid}/{sub.relative_to(run_dir)}"
                        tf.add(str(sub), arcname=arc, recursive=False)
            else:
                arc = f"{rid}/{p.relative_to(run_dir)}"
                tf.add(str(p), arcname=arc, recursive=False)

    # ensure non-empty
    if not cache.is_file() or cache.stat().st_size == 0:
        try:
            cache.unlink(missing_ok=True)
        except Exception:
            pass
        return None
    return cache

def _vsp_p463_sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

# --- routes ---
try:
    from flask import request, jsonify, send_file, abort
except Exception:
    request = None
    jsonify = None
    send_file = None
    abort = None

@app.get("/api/vsp/export_csv")
def api_vsp_export_csv():
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"missing rid and no latest rid found"}), 400

    run_dir = _vsp_p463_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    f = _vsp_p463_pick_csv(run_dir)
    if not f:
        return jsonify({"ok":0, "err":"findings_unified.csv not found", "rid":rid}), 404

    dl = f"findings_unified_{rid}.csv"
    return send_file(str(f), mimetype="text/csv", as_attachment=True, download_name=dl)

@app.get("/api/vsp/export_tgz")
def api_vsp_export_tgz():
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"missing rid and no latest rid found"}), 400

    run_dir = _vsp_p463_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    tgz = _vsp_p463_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build export tgz", "rid":rid}), 500

    dl = f"vsp_export_{rid}.tgz"
    return send_file(str(tgz), mimetype="application/gzip", as_attachment=True, download_name=dl)

@app.get("/api/vsp/sha256")
def api_vsp_sha256():
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"missing rid and no latest rid found"}), 400

    run_dir = _vsp_p463_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    tgz = _vsp_p463_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build export tgz", "rid":rid}), 500

    return jsonify({"ok":1, "rid":rid, "file":tgz.name, "sha256":_vsp_p463_sha256_file(tgz), "bytes":tgz.stat().st_size})
# --- /VSP_P463_EXPORTS_CSV_TGZ_SHA256_V1 ---
'''

# insert before __main__ if present; else append
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', s)
if m:
    i = m.start()
    s2 = s[:i] + block + "\n\n" + s[i:]
else:
    s2 = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched P463 in vsp_demo_app.py")
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

# quick checks (pick latest rid via /api/vsp/runs if available)
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 - <<'PY' || true
import sys,json
try:
    j=json.load(sys.stdin)
    items=j.get("items") or []
    if items:
        print(items[0].get("rid","") or "")
except Exception:
    pass
PY
)"

echo "[INFO] RID=$RID" | tee -a "$OUT/log.txt"

for u in \
  "$BASE/api/vsp/export_csv?rid=$RID" \
  "$BASE/api/vsp/export_tgz?rid=$RID" \
  "$BASE/api/vsp/sha256?rid=$RID" \
  "$BASE/api/vsp/export_csv" \
  "$BASE/api/vsp/export_tgz" \
  "$BASE/api/vsp/sha256"
do
  code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 10 "$u" || echo 000)"
  echo "[CHECK] $code $u" | tee -a "$OUT/log.txt"
done

echo "[OK] P463 done. See $OUT/log.txt" | tee -a "$OUT/log.txt"
