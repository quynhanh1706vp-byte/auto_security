#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_export_${TS}"
echo "[BACKUP] ${F}.bak_export_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_EXPORT_TGZ_CSV_SHA_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block = r'''
# VSP_P1_EXPORT_TGZ_CSV_SHA_V1
from flask import request, jsonify, send_file
import tarfile, hashlib, tempfile, time
from pathlib import Path

def _vsp_try_resolve_run_dir(rid: str):
    # Prefer existing resolver if present
    for name in ("resolve_run_dir", "vsp_resolve_run_dir", "get_run_dir_by_rid", "resolve_rid_to_dir"):
        fn = globals().get(name)
        if callable(fn):
            try:
                d = fn(rid)
                if d:
                    d = Path(d)
                    if d.exists():
                        return d
            except Exception:
                pass

    # Fallback scan
    bases = [
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
    ]
    env = os.environ.get("VSP_RUNS_ROOT")
    if env:
        bases.insert(0, Path(env))
    for b in bases:
        try:
            d = b / rid
            if d.exists():
                return d
            # search shallow
            for cand in b.glob(f"**/{rid}"):
                if cand.is_dir():
                    return cand
        except Exception:
            continue
    return None

def _sha256_path(fp: Path) -> str:
    h = hashlib.sha256()
    with fp.open("rb") as f:
        for ch in iter(lambda: f.read(1024*1024), b""):
            h.update(ch)
    return h.hexdigest()

@app.route("/api/vsp/export_tgz")
def vsp_export_tgz():
    rid = request.args.get("rid","").strip()
    scope = (request.args.get("scope","reports") or "reports").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing rid"}), 400
    run_dir = _vsp_try_resolve_run_dir(rid)
    if not run_dir:
        return jsonify({"ok": False, "err": "rid not found", "rid": rid}), 404

    src = run_dir if scope == "run" else (run_dir / "reports")
    if not src.exists():
        return jsonify({"ok": False, "err": "scope not found", "scope": scope}), 404

    out_dir = Path("out_ci/exports")
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{rid}.{scope}.{ts}.tgz"

    with tarfile.open(out, "w:gz") as tar:
        tar.add(src, arcname=src.name)

    return send_file(out, mimetype="application/gzip", as_attachment=True, download_name=out.name)

@app.route("/api/vsp/export_csv")
def vsp_export_csv():
    rid = request.args.get("rid","").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing rid"}), 400
    run_dir = _vsp_try_resolve_run_dir(rid)
    if not run_dir:
        return jsonify({"ok": False, "err": "rid not found", "rid": rid}), 404

    # Prefer existing CSV
    csvp = run_dir / "reports" / "findings_unified.csv"
    if csvp.exists():
        return send_file(csvp, mimetype="text/csv", as_attachment=True, download_name=f"{rid}.findings_unified.csv")

    # Generate minimal CSV from findings_unified.json
    import csv, json
    jp = run_dir / "reports" / "findings_unified.json"
    if not jp.exists():
        jp = run_dir / "findings_unified.json"
    items = []
    try:
        obj = json.loads(jp.read_text(encoding="utf-8", errors="replace"))
        items = obj.get("items") if isinstance(obj, dict) else []
        if items is None: items=[]
    except Exception:
        items = []

    out_dir = Path("out_ci/exports")
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    out = out_dir / f"{rid}.findings_unified.{ts}.csv"

    cols = ["tool","severity","title","rule_id","file","line","message"]
    with out.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for it in items:
            if not isinstance(it, dict): 
                continue
            w.writerow({
                "tool": it.get("tool",""),
                "severity": it.get("severity",""),
                "title": it.get("title","") or it.get("name",""),
                "rule_id": it.get("rule_id","") or it.get("id",""),
                "file": it.get("path","") or it.get("file",""),
                "line": it.get("line","") or it.get("start_line",""),
                "message": it.get("message","") or it.get("description",""),
            })

    return send_file(out, mimetype="text/csv", as_attachment=True, download_name=out.name)

@app.route("/api/vsp/sha256")
def vsp_sha256():
    rid = request.args.get("rid","").strip()
    name = request.args.get("name","").strip()
    if not rid or not name:
        return jsonify({"ok": False, "err": "missing rid or name"}), 400
    run_dir = _vsp_try_resolve_run_dir(rid)
    if not run_dir:
        return jsonify({"ok": False, "err": "rid not found", "rid": rid}), 404

    # allow only relative under run_dir
    rel = name.lstrip("/").replace("..","")
    fp = (run_dir / rel).resolve()
    if not str(fp).startswith(str(run_dir.resolve())):
        return jsonify({"ok": False, "err": "invalid name"}), 400
    if not fp.exists():
        return jsonify({"ok": False, "err": "file not found", "name": rel}), 404

    return jsonify({"ok": True, "rid": rid, "name": rel, "sha256": _sha256_path(fp), "bytes": fp.stat().st_size})
'''.lstrip("\n")

# insert before main guard if exists, else append
m = re.search(r"^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s, flags=re.M)
if m:
    s = s[:m.start()] + block + "\n\n" + s[m.start():]
else:
    s = s.rstrip() + "\n\n" + block + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK: vsp_demo_app.py"

echo "[NEXT] restart UI: sudo systemctl restart vsp-ui-8910.service"
