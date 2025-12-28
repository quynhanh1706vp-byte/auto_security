#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p463fix_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need ls; need head; need grep; need curl
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

ok(){ echo "[OK] $*" | tee -a "$OUT/log.txt"; }
err(){ echo "[ERR] $*" | tee -a "$OUT/log.txt"; exit 2; }

# ========== [A] RESTORE vsp_demo_app.py to last backup (undo broken P463b) ==========
APP="vsp_demo_app.py"
bak="$(ls -1t out_ci/p463b_*/${APP}.bak_* out_ci/p463_*/${APP}.bak_* 2>/dev/null | head -n1 || true)"
[ -n "$bak" ] || err "Cannot find backup for $APP under out_ci/p463*/"
cp -f "$bak" "$APP"
ok "restored $APP <= $bak"

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"
ok "py_compile $APP PASS"

# ========== [B] PATCH wsgi gateway by OVERRIDING routes (no regex delete) ==========
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || err "missing $W"
cp -f "$W" "$OUT/${W}.bak_${TS}"
ok "backup $W => $OUT/${W}.bak_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P463FIX_EXPORTS_OVERRIDE_V1"
if MARK in s:
    print("[OK] already patched exports override")
    sys.exit(0)

block = r'''
# --- VSP_P463FIX_EXPORTS_OVERRIDE_V1 ---
def _vsp_p463fix_candidate_roots():
    from pathlib import Path
    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE"),
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path(__file__).resolve().parent / "out_ci",
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

def _vsp_p463fix_latest_rid():
    # bounded scan under SECURITY_BUNDLE for VSP_CI_*
    import os
    best=None
    for root in ["/home/test/Data/SECURITY_BUNDLE", "/home/test/Data/SECURITY_BUNDLE/ui/out_ci"]:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, _ in os.walk(root):
            # prune deep huge dirs
            if "/.venv/" in dirpath or "/venv/" in dirpath or "/node_modules/" in dirpath:
                dirnames[:] = []
                continue
            for dn in dirnames:
                if dn.startswith("VSP_CI_"):
                    if best is None or dn > best:
                        best = dn
            # prune after some depth
            if dirpath.count(os.sep) - root.count(os.sep) > 6:
                dirnames[:] = []
    return best

def _vsp_p463fix_find_run_dir(rid: str):
    import os
    from pathlib import Path
    if not rid:
        return None
    rid = str(rid).strip()
    for base in _vsp_p463fix_candidate_roots():
        try:
            for d in base.rglob(rid):
                if d.is_dir() and d.name == rid:
                    return d
        except Exception:
            pass
    return None

def _vsp_p463fix_pick_csv(run_dir):
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

def _vsp_p463fix_exports_cache_dir():
    from pathlib import Path
    root = Path(__file__).resolve().parent
    d = root / "out_ci" / "exports_cache"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _vsp_p463fix_build_tgz_cached(run_dir, rid: str):
    import tarfile, os, time
    from pathlib import Path
    rid = str(rid).strip() or "RID_UNKNOWN"
    cache_dir = _vsp_p463fix_exports_cache_dir()
    tmp = cache_dir / f".tmp_export_{rid}.{os.getpid()}.tgz"
    out = cache_dir / f"export_{rid}.tgz"

    try:
        if out.is_file() and out.stat().st_size > 0:
            return out
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

    with tarfile.open(tmp, "w:gz") as tf:
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

    if not tmp.is_file() or tmp.stat().st_size == 0:
        try: tmp.unlink(missing_ok=True)
        except Exception: pass
        return None

    tmp.replace(out)
    return out

def _vsp_p463fix_sha256_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024*1024), b""):
            h.update(chunk)
    return h.hexdigest()

def _vsp_p463fix_export_csv():
    from flask import request, jsonify, send_file
    rid = (request.args.get("rid","") or "").strip() or (_vsp_p463fix_latest_rid() or "")
    if not rid:
        return jsonify({"ok":0, "err":"no rid (cannot auto-detect latest)"}), 400
    run_dir = _vsp_p463fix_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404
    f = _vsp_p463fix_pick_csv(run_dir)
    if not f:
        return jsonify({"ok":0, "err":"findings_unified.csv not found", "rid":rid, "run_dir":str(run_dir)}), 404
    dl = f"findings_unified_{rid}.csv"
    return send_file(str(f), mimetype="text/csv", as_attachment=True, download_name=dl)

def _vsp_p463fix_export_tgz():
    from flask import request, jsonify, send_file
    rid = (request.args.get("rid","") or "").strip() or (_vsp_p463fix_latest_rid() or "")
    if not rid:
        return jsonify({"ok":0, "err":"no rid (cannot auto-detect latest)"}), 400
    run_dir = _vsp_p463fix_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404
    tgz = _vsp_p463fix_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build tgz", "rid":rid}), 500
    dl = f"vsp_export_{rid}.tgz"
    return send_file(str(tgz), mimetype="application/gzip", as_attachment=True, download_name=dl)

def _vsp_p463fix_sha256():
    from flask import request, jsonify
    rid = (request.args.get("rid","") or "").strip() or (_vsp_p463fix_latest_rid() or "")
    if not rid:
        return jsonify({"ok":0, "err":"no rid (cannot auto-detect latest)"}), 400
    run_dir = _vsp_p463fix_find_run_dir(rid)
    if not run_dir:
        return jsonify({"ok":0, "err":"rid not found", "rid":rid}), 404
    tgz = _vsp_p463fix_build_tgz_cached(run_dir, rid)
    if not tgz:
        return jsonify({"ok":0, "err":"failed to build tgz", "rid":rid}), 500
    return jsonify({"ok":1, "rid":rid, "file":tgz.name, "bytes":tgz.stat().st_size, "sha256":_vsp_p463fix_sha256_file(tgz)})

def _vsp_p463fix_override_or_add(path: str, methods: list, handler):
    """
    Replace existing endpoint for (path, methods) if present; else add_url_rule.
    """
    try:
        for rule in list(app.url_map.iter_rules()):
            if rule.rule == path:
                # match any method in methods
                if any(m in rule.methods for m in methods):
                    ep = rule.endpoint
                    app.view_functions[ep] = handler
                    return ("replaced", ep)
    except Exception:
        pass

    # not found: add new
    ep = f"vsp_p463fix_{path.strip('/').replace('/','_')}"
    app.add_url_rule(path, endpoint=ep, view_func=handler, methods=methods)
    return ("added", ep)

def _vsp_p463fix_install():
    r1 = _vsp_p463fix_override_or_add("/api/vsp/export_csv", ["GET"], _vsp_p463fix_export_csv)
    r2 = _vsp_p463fix_override_or_add("/api/vsp/export_tgz", ["GET"], _vsp_p463fix_export_tgz)
    r3 = _vsp_p463fix_override_or_add("/api/vsp/sha256", ["GET"], _vsp_p463fix_sha256)
    try:
        # optional: expose diagnostics header
        pass
    except Exception:
        pass
    return (r1, r2, r3)

_vsp_p463fix_install()
# --- /VSP_P463FIX_EXPORTS_OVERRIDE_V1 ---
'''

# insert after imports block best-effort
m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", s)
if m:
    head=m.group(0)
    rest=s[len(head):]
    s = head + block + "\n" + rest
else:
    s = block + "\n" + s

p.write_text(s, encoding="utf-8")
print("[OK] injected exports override into wsgi")
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"
ok "py_compile $W PASS"

# restart service
if command -v systemctl >/dev/null 2>&1; then
  ok "restart $SVC"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

# smoke test exports (GET, and headers for attachments)
ok "TEST sha256 (GET)"
curl -sS --connect-timeout 2 --max-time 20 "$BASE/api/vsp/sha256" | head -c 200 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"

ok "TEST export_csv headers"
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 20 "$BASE/api/vsp/export_csv" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

ok "TEST export_tgz headers"
curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 20 "$BASE/api/vsp/export_tgz" | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Content-Disposition:/{print}' | tee -a "$OUT/log.txt"

ok "DONE: see $OUT/log.txt"
