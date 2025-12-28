#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_audit_api_${TS}"
echo "[BACKUP] ${APP}.bak_audit_api_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# idempotent: remove older block if exists
s = re.sub(
    r"\n# ===================== VSP_P1_AUDIT_PACK_API_V1_SAFEAPPEND =====================.*?"
    r"# ===================== /VSP_P1_AUDIT_PACK_API_V1_SAFEAPPEND =====================\n",
    "\n",
    s,
    flags=re.S,
)

block = r'''
# ===================== VSP_P1_AUDIT_PACK_API_V1_SAFEAPPEND =====================
# /api/vsp/audit_pack?rid=<RID> -> tgz containing audit evidence + manifest
import os, json, time, tarfile, tempfile
from pathlib import Path
from flask import request, send_file, jsonify

def _vsp_audit_read_release_latest():
    cands = []
    envp = os.environ.get("VSP_RELEASE_LATEST_JSON", "").strip()
    if envp:
        cands.append(envp)
    cands += [
        "/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json",
        str(Path(__file__).resolve().parent / "out_ci" / "releases" / "release_latest.json"),
    ]
    for x in cands:
        try:
            rp = Path(x)
            if rp.is_file() and rp.stat().st_size > 0:
                return json.loads(rp.read_text(encoding="utf-8", errors="replace"))
        except Exception:
            continue
    return {}

def _vsp_audit_sanitize_ts(ts: str) -> str:
    t = (ts or "").strip()
    if not t:
        return ""
    t = t.replace("T", "_").replace(":", "").replace("+", "p")
    t = re.sub(r"[^0-9A-Za-z._-]+", "", t)
    return t

def _vsp_audit_suffix(relj: dict) -> str:
    ts = _vsp_audit_sanitize_ts(str(relj.get("release_ts") or "").strip()) or ("norel-" + time.strftime("%Y%m%d_%H%M%S"))
    sha = str(relj.get("release_sha") or "").strip()
    sha12 = sha[:12] if sha else "unknown"
    if ts.startswith("norel-"):
        return f"_{ts}_sha-{sha12}"
    return f"_rel-{ts}_sha-{sha12}"

def _vsp_find_run_dir(rid: str) -> Path | None:
    rid = (rid or "").strip()
    if not rid:
        return None
    # allow rid to be a path
    try:
        rp = Path(rid)
        if rp.is_dir():
            return rp
    except Exception:
        pass

    roots = [
        Path("/home/test/Data/SECURITY_BUNDLE/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/out"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out"),
    ]
    for root in roots:
        try:
            d = root / rid
            if d.is_dir():
                return d
        except Exception:
            continue
    return None

def _vsp_add_path(tar: tarfile.TarFile, src: Path, arc_prefix: str, manifest: dict):
    try:
        if src.is_file():
            tar.add(src.as_posix(), arcname=f"{arc_prefix}/{src.name}")
            manifest["included"].append(str(src))
        elif src.is_dir():
            # add directory recursively under its own name
            tar.add(src.as_posix(), arcname=f"{arc_prefix}/{src.name}")
            manifest["included"].append(str(src) + "/")
        else:
            manifest["missing"].append(str(src))
    except Exception as e:
        manifest["errors"].append({"path": str(src), "err": str(e)})

def _vsp_register_audit_pack_api(app):
    if not app:
        return
    if getattr(app, "__vsp_audit_pack_api_v1", False):
        return

    # avoid duplicate rule
    try:
        for r in app.url_map.iter_rules():
            if getattr(r, "rule", "") == "/api/vsp/audit_pack":
                app.__vsp_audit_pack_api_v1 = True
                return
    except Exception:
        pass

    def _handler():
        rid = (request.args.get("rid") or request.args.get("run_id") or "").strip()
        if not rid:
            return jsonify({"ok": False, "err": "missing rid"}), 400

        run_dir = _vsp_find_run_dir(rid)
        if not run_dir:
            return jsonify({"ok": False, "err": f"RUN_DIR_NOT_FOUND rid={rid}"}), 404

        relj = _vsp_audit_read_release_latest()
        suffix = _vsp_audit_suffix(relj)
        fname = f"AUDIT_{rid}{suffix}.tgz"

        tmpd = Path(tempfile.mkdtemp(prefix="vsp_audit_"))
        out = tmpd / fname

        manifest = {
            "ok": True,
            "rid": rid,
            "run_dir": str(run_dir),
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "release": {
                "release_ts": relj.get("release_ts",""),
                "release_sha": relj.get("release_sha",""),
                "release_pkg": relj.get("release_pkg",""),
            },
            "included": [],
            "missing": [],
            "errors": [],
        }

        arc_prefix = f"AUDIT_{rid}"

        # Candidate core files
        candidates = [
            run_dir / "run_gate_summary.json",
            run_dir / "run_gate.json",
            run_dir / "findings_unified.json",
            run_dir / "findings_unified.csv",
            run_dir / "findings_unified.sarif",
            run_dir / "SUMMARY.txt",
            run_dir / "reports",
            run_dir / "evidence",
        ]

        # Also include reports/findings_unified.* if the pipeline puts them there
        candidates += [
            run_dir / "reports" / "findings_unified.csv",
            run_dir / "reports" / "findings_unified.sarif",
            run_dir / "reports" / "findings_unified.html",
        ]

        # release_latest.json
        for rp in [
            Path("/home/test/Data/SECURITY_BUNDLE/out_ci/releases/release_latest.json"),
            Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/releases/release_latest.json"),
            Path(__file__).resolve().parent / "out_ci" / "releases" / "release_latest.json",
        ]:
            if rp.is_file() and rp.stat().st_size > 0:
                candidates.append(rp)
                break

        # build tgz
        with tarfile.open(out.as_posix(), "w:gz") as tar:
            for c in candidates:
                _vsp_add_path(tar, c, arc_prefix, manifest)

            # write manifest into archive
            man_path = tmpd / "AUDIT_MANIFEST.json"
            man_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
            tar.add(man_path.as_posix(), arcname=f"{arc_prefix}/AUDIT_MANIFEST.json")

        resp = send_file(out.as_posix(), as_attachment=True, download_name=fname, mimetype="application/gzip")
        # mirror build identity headers (nice for audit)
        if relj.get("release_ts"):  resp.headers["X-VSP-RELEASE-TS"]  = str(relj.get("release_ts"))
        if relj.get("release_sha"): resp.headers["X-VSP-RELEASE-SHA"] = str(relj.get("release_sha"))
        if relj.get("release_pkg"): resp.headers["X-VSP-RELEASE-PKG"] = str(relj.get("release_pkg"))
        resp.headers["X-VSP-AUDIT"] = "ok"
        return resp

    app.add_url_rule("/api/vsp/audit_pack", "vsp_audit_pack_v1", _handler, methods=["GET"])
    app.__vsp_audit_pack_api_v1 = True

# register at EOF (safe)
try:
    _vsp_register_audit_pack_api(globals().get("app") or globals().get("application"))
except Exception:
    pass
# ===================== /VSP_P1_AUDIT_PACK_API_V1_SAFEAPPEND =====================
'''

# append at EOF
s = s.rstrip() + "\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended audit_pack API block")
PY

echo "== compile check =="
python3 -m py_compile "$APP"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] audit_pack API installed."
