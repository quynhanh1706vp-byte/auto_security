#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v sudo >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_p554_${TS}"
echo "[OK] backup => ${APP}.bak_p554_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

routes = [
  "support_bundle_v1","bundle_support_v1","export_support_bundle_v1",
]
pat = re.compile(
  r"(?ms)^@app\.route\([^\n]*?/api/vsp/(?:%s)[^\n]*\)\n.*?(?=^@app\.route|\Z)" % "|".join(routes)
)
s2 = pat.sub("", s)

new_block = r'''
# =========================
# P554: Support bundle export (tgz) by RID
# - returns real application/gzip tarball (not JSON not allowed)
# - includes: run artifacts + basic UI evidence pointers
# =========================
import io, tarfile, hashlib, time
from flask import request, Response, jsonify

def _p554_allow_bundle():
    # default allow; set VSP_UI_BUNDLE_ALLOW=0 to disable
    v = os.environ.get("VSP_UI_BUNDLE_ALLOW", "1").strip().lower()
    return v not in ("0","false","no","off")

def _p554_safe_arc(base: Path, f: Path, prefix: str):
    try:
        rel = f.resolve().relative_to(base.resolve())
    except Exception:
        rel = f.name
    # normalize separators
    rel = Path(str(rel).lstrip("/"))
    return str(Path(prefix) / rel)

def _p554_pick_files(run_dir: Path):
    """Return list[Path] of files to include from run_dir."""
    files = []
    # prefer key artifacts
    must = [
        "run_gate_summary.json", "run_gate.json", "verdict_4t.json",
        "findings_unified.json", "findings_unified.csv", "findings_unified.sarif",
        "run_manifest.json", "run_evidence_index.json",
    ]
    for nm in must:
        f = _p552_find_first(run_dir, [nm]) if "_p552_find_first" in globals() else None
        if f and f.is_file():
            files.append(f)

    # include reports if exist
    for nm in ["report.html","report.pdf","findings_unified.html","findings_unified.pdf"]:
        f = _p552_find_first(run_dir, [nm]) if "_p552_find_first" in globals() else None
        if f and f.is_file():
            files.append(f)

    # include common directories (bounded)
    # tool logs often under subfolders like semgrep/, kics/, codeql/...
    # add any *.log, *.txt, *.json, *.sarif, *.csv under run_dir up to limits
    exts = {".log",".txt",".json",".sarif",".csv",".html",".pdf",".yml",".yaml"}
    for f in run_dir.glob("**/*"):
        if not f.is_file():
            continue
        if f.suffix.lower() not in exts:
            continue
        # skip huge binaries
        try:
            sz = f.stat().st_size
        except Exception:
            continue
        if sz > 25 * 1024 * 1024:  # 25MB per-file cap
            continue
        files.append(f)

    # de-dupe keep order
    seen=set()
    out=[]
    for f in files:
        try:
            key=str(f.resolve())
        except Exception:
            key=str(f)
        if key in seen:
            continue
        seen.add(key)
        out.append(f)
    return out

def _p554_build_index(run_dir: Path, included_paths, meta: dict):
    idx = {
        "rid": meta.get("rid"),
        "generated_at": int(time.time()),
        "run_dir": str(run_dir),
        "release_ts": meta.get("release_ts",""),
        "release_sha": meta.get("release_sha",""),
        "items": []
    }
    for it in included_paths:
        try:
            st = it.stat()
            idx["items"].append({
                "path": str(it),
                "size": int(st.st_size),
                "mtime": int(st.st_mtime),
            })
        except Exception:
            idx["items"].append({"path": str(it)})
    return idx

def _p554_support_bundle_common(rid: str):
    if not _p554_allow_bundle():
        return jsonify({"ok": False, "err": "bundle_disabled"}), 403

    run_dir = _p552_resolve_run_dir(rid) if "_p552_resolve_run_dir" in globals() else None
    if not run_dir:
        return jsonify({"ok": False, "err": "rid_not_found", "rid": rid}), 404

    meta = {
        "rid": rid,
        "release_ts": request.environ.get("HTTP_X_VSP_RELEASE_TS", "") or "",
        "release_sha": request.environ.get("HTTP_X_VSP_RELEASE_SHA", "") or "",
    }

    picked = _p554_pick_files(run_dir)

    # add generated evidence index into tar even if not present
    idx = _p554_build_index(run_dir, picked, meta)
    idx_bytes = (json.dumps(idx, ensure_ascii=False, indent=2) + "\n").encode("utf-8", errors="replace")

    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        # put index first
        ti = tarfile.TarInfo(name=f"support_bundle/{rid}/evidence_index_generated.json")
        ti.size = len(idx_bytes)
        ti.mtime = int(time.time())
        tf.addfile(ti, io.BytesIO(idx_bytes))

        # add picked files under support_bundle/<rid>/run/...
        for f in picked:
            try:
                arc = _p554_safe_arc(run_dir, f, f"support_bundle/{rid}/run")
                tf.add(str(f), arcname=arc, recursive=False)
            except Exception:
                pass

        # optionally include UI config pointers (do NOT include full production.env by default)
        ui_root = Path("/home/test/Data/SECURITY_BUNDLE/ui")
        note = (
            "NOTE: UI config/env files are not included by default to avoid leaking secrets.\n"
            "Set VSP_UI_BUNDLE_INCLUDE_UI_CONFIG=1 to include ui/config/*.env (use with caution).\n"
        ).encode("utf-8")
        ti2 = tarfile.TarInfo(name=f"support_bundle/{rid}/README_SUPPORT_BUNDLE.txt")
        ti2.size = len(note); ti2.mtime = int(time.time())
        tf.addfile(ti2, io.BytesIO(note))

        inc_cfg = os.environ.get("VSP_UI_BUNDLE_INCLUDE_UI_CONFIG","0").strip().lower() in ("1","true","yes","on")
        if inc_cfg and ui_root.is_dir():
            cfg_dir = ui_root / "config"
            if cfg_dir.is_dir():
                for f in cfg_dir.glob("*.env"):
                    try:
                        if f.is_file() and f.stat().st_size < 2*1024*1024:
                            tf.add(str(f), arcname=f"support_bundle/{rid}/ui_config/{f.name}", recursive=False)
                    except Exception:
                        pass

    data = buf.getvalue()
    # basic sanity: gzip magic should be 1f8b
    if not (len(data) >= 2 and data[0] == 0x1f and data[1] == 0x8b):
        return jsonify({"ok": False, "err": "bundle_build_failed"}), 500

    fn = f"support_bundle_{rid}.tgz"
    return Response(
        data,
        mimetype="application/gzip",
        headers={"Content-Disposition": f'attachment; filename="{fn}"'}
    )

@app.route("/api/vsp/support_bundle_v1")
@app.route("/api/vsp/bundle_support_v1")
@app.route("/api/vsp/export_support_bundle_v1")
def api_vsp_support_bundle_v1():
    rid = request.args.get("rid","").strip()
    if not rid:
        return jsonify({"ok": False, "err": "missing_rid"}), 400
    return _p554_support_bundle_common(rid)
'''

m = re.search(r"(?m)^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s2)
if m:
    out = s2[:m.start()] + new_block + "\n\n" + s2[m.start():]
else:
    out = s2 + "\n\n" + new_block + "\n"

p.write_text(out, encoding="utf-8")
print("[OK] patched support bundle routes")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile"

if command -v sudo >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
fi

# wait port (avoid the earlier quick-probe race)
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/vsp5" >/dev/null; then
    echo "[OK] UI up"
    break
  fi
  sleep 1
done

RID="${RID:-VSP_CI_20251219_092640}"
echo "== probe bundle (magic+size) =="
tmp="/tmp/p554_bundle_${RID}.tgz"
curl -fsS --connect-timeout 2 --max-time 30 "$BASE/api/vsp/support_bundle_v1?rid=$RID" -o "$tmp"
python3 - <<'PY' "$tmp"
import sys,binascii,os
p=sys.argv[1]
b=open(p,'rb').read(2)
print("magic=",binascii.hexlify(b).decode(),"size=",os.path.getsize(p))
PY
