#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need curl; need grep
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P463B_EXPORTS_FIX_LATESTRID_V1"

helper = r'''
# --- VSP_P463B_EXPORTS_FIX_LATESTRID_V1 ---
def _vsp_p463b_candidate_roots():
    from pathlib import Path
    import os
    roots = []
    for k in ("VSP_RUNS_ROOT","SECURITY_BUNDLE_OUT","SECURITY_BUNDLE_OUT_CI"):
        v = os.getenv(k, "").strip()
        if v:
            roots.append(Path(v))
    roots += [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path(__file__).resolve().parent / "out_ci",
        Path("/home/test/Data"),
    ]
    out=[]
    seen=set()
    for r in roots:
        try: r=r.resolve()
        except Exception: pass
        k=str(r)
        if k in seen: continue
        seen.add(k)
        if r.exists(): out.append(r)
    return out

def _vsp_p463b_latest_rid_from_runs_index():
    """
    Preferred: find a JSON that already knows the latest RID (runs index/cache).
    Search under ui/out_ci recursively for runs*.json / runs_index*.json.
    """
    import json
    from pathlib import Path
    ui_out = Path(__file__).resolve().parent / "out_ci"
    pats = ("runs", "runs_index", "runs_v", "runs_cache")
    cands = []
    if ui_out.exists():
        for f in ui_out.rglob("*.json"):
            n = f.name.lower()
            if any(k in n for k in pats):
                cands.append(f)
    # newest first
    cands.sort(key=lambda x: x.stat().st_mtime if x.exists() else 0, reverse=True)
    for f in cands[:30]:
        try:
            j = json.loads(f.read_text(encoding="utf-8", errors="replace"))
            items = j.get("items") or j.get("runs") or []
            if isinstance(items, list) and items:
                rid = (items[0].get("rid") if isinstance(items[0], dict) else "") or ""
                rid = str(rid).strip()
                if rid.startswith("VSP_"):
                    return rid
        except Exception:
            continue
    return None

def _vsp_p463b_latest_rid_fallback_scan():
    """
    Fallback: recursive scan for folder names VSP_CI_* under candidate roots.
    """
    best=None
    for base in _vsp_p463b_candidate_roots():
        try:
            for d in base.rglob("VSP_CI_*"):
                if d.is_dir():
                    name = d.name
                    if (best is None) or (name > best):
                        best = name
        except Exception:
            pass
    return best

def _vsp_p463b_latest_rid():
    rid = _vsp_p463b_latest_rid_from_runs_index()
    if rid:
        return rid
    return _vsp_p463b_latest_rid_fallback_scan()

def _vsp_p463b_find_run_dir(rid: str):
    from pathlib import Path
    if not rid:
        return None
    rid = str(rid).strip()
    # direct recursive find (bounded)
    for base in _vsp_p463b_candidate_roots():
        try:
            for d in base.rglob(rid):
                if d.is_dir() and d.name == rid:
                    return d
        except Exception:
            pass
    return None

def _vsp_p463b_pick_csv(run_dir):
    cands = [
        run_dir / "reports" / "findings_unified.csv",
        run_dir / "report"  / "findings_unified.csv",
        run_dir / "findings_unified.csv",
    ]
    for f in cands:
        try:
            if f.is_file() and f.stat().st_size > 0:
                return f
        except Exception:
            pass
    return None

def _vsp_p463b_exports_cache_dir():
    from pathlib import Path
    root = Path(__file__).resolve().parent
    d = root / "out_ci" / "exports_cache"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp_p463b_build_tgz_cached(run_dir, rid: str):
    import tarfile
    rid = str(rid).strip() or "RID_UNKNOWN"
    cache = _vsp_p463b_exports_cache_dir() / f"export_{rid}.tgz"
    try:
        if cache.is_file() and cache.stat().st_size > 0:
            return cache
    except Exception:
        pass

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
        "reports",
    ]

    with tarfile.open(cache, "w:gz") as tf:
        for rel in include:
            p = (run_dir / rel)
            if not p.exists():
                continue
            if p.is_dir():
                for sub in p.rglob("*"):
                    if sub.is_file():
                        arc = f"{rid}/{sub.relative_to(run_dir)}"
                        tf.add(str(sub), arcname=arc, recursive=False)
            else:
                arc = f"{rid}/{p.relative_to(run_dir)}"
                tf.add(str(p), arcname=arc, recursive=False)

    if not cache.is_file() or cache.stat().st_size == 0:
        try: cache.unlink(missing_ok=True)
        except Exception: pass
        return None
    return cache

def _vsp_p463b_sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()
# --- /VSP_P463B_EXPORTS_FIX_LATESTRID_V1 ---
'''

routes = r'''
# --- VSP_P463B_EXPORT_ROUTES_V1 ---
@app.get("/api/vsp/export_csv")
def api_vsp_export_csv_v463b():
    from flask import request, jsonify, send_file
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463b_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"no rid (and cannot auto-detect latest)"}), 400

    run_dir = _vsp_p463b_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    f = _vsp_p463b_pick_csv(run_dir)
    if not f:
        return jsonify({"ok":0, "err":"findings_unified.csv not found", "rid":rid, "run_dir":str(run_dir)}), 404

    dl = f"findings_unified_{rid}.csv"
    return send_file(str(f), mimetype="text/csv", as_attachment=True, download_name=dl)

@app.get("/api/vsp/export_tgz")
def api_vsp_export_tgz_v463b():
    from flask import request, jsonify, send_file
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463b_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"no rid (and cannot auto-detect latest)"}), 400

    run_dir = _vsp_p463b_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    tgz = _vsp_p463b_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build tgz", "rid":rid}), 500

    dl = f"vsp_export_{rid}.tgz"
    return send_file(str(tgz), mimetype="application/gzip", as_attachment=True, download_name=dl)

@app.get("/api/vsp/sha256")
def api_vsp_sha256_v463b():
    from flask import request, jsonify
    rid = (request.args.get("rid","") or "").strip()
    if not rid:
        rid = _vsp_p463b_latest_rid() or ""
    if not rid:
        return jsonify({"ok":0, "err":"no rid (and cannot auto-detect latest)"}), 400

    run_dir = _vsp_p463b_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404

    tgz = _vsp_p463b_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build tgz", "rid":rid}), 500

    return jsonify({"ok":1, "rid":rid, "file":tgz.name, "bytes":tgz.stat().st_size, "sha256":_vsp_p463b_sha256_file(tgz)})
# --- /VSP_P463B_EXPORT_ROUTES_V1 ---
'''

def remove_existing_route_block(text: str, path: str) -> str:
    # Remove any existing @app.get("path") function block to avoid duplicates.
    # Pattern: decorator line + following def ... until next @app. or end.
    pat = re.compile(
        r'(?s)^\s*@app\.(?:get|route)\(\s*["\']' + re.escape(path) + r'["\'].*?\)\s*\n\s*def\s+.*?:\s*\n.*?(?=^\s*@app\.|\Z)',
        re.M
    )
    return pat.sub("", text)

# 1) ensure helper once (before routes)
if MARK not in s:
    # put after imports if possible
    m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", s)
    if m:
        head=m.group(0)
        rest=s[len(head):]
        s = head + helper + "\n" + rest
    else:
        s = helper + "\n" + s

# 2) remove old routes (export_csv/export_tgz/sha256) to avoid duplicate route registration
for path in ("/api/vsp/export_csv", "/api/vsp/export_tgz", "/api/vsp/sha256"):
    s = remove_existing_route_block(s, path)

# 3) append new routes near end but before __main__ if possible
m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*["\']__main__["\']\s*:\s*$', s)
if m:
    i = m.start()
    s = s[:i] + routes + "\n\n" + s[i:]
else:
    s = s.rstrip() + "\n\n" + routes + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] patched P463b (routes replaced + latest rid auto)")
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== [TEST] GET (not HEAD) ==" | tee -a "$OUT/log.txt"
for u in \
  "$BASE/api/vsp/sha256" \
  "$BASE/api/vsp/export_csv" \
  "$BASE/api/vsp/export_tgz"
do
  echo "-- $u" | tee -a "$OUT/log.txt"
  curl -sS --connect-timeout 2 --max-time 20 "$u" | head -c 300 | tr '\n' ' ' | tee -a "$OUT/log.txt"
  echo "" | tee -a "$OUT/log.txt"
done

echo "[OK] P463b done. log: $OUT/log.txt"
