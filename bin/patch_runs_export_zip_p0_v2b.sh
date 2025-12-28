#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_exportzip_v2b_${TS}"
echo "[BACKUP] ${APP}.bak_exportzip_v2b_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

APP = Path("vsp_demo_app.py")
s = APP.read_text(encoding="utf-8", errors="replace")

MARK1="VSP_EXPORT_ZIP_P0_V1"
MARK2="VSP_EXPORT_ZIP_P0_V2"
MARKB="VSP_EXPORT_ZIP_P0_V2B"

def strip_block(text, mark):
    pat = re.compile(rf"\n# === {re.escape(mark)} ===.*?\n# === /{re.escape(mark)} ===\n", re.S)
    return pat.sub("\n", text)

# remove older blocks if any
s = strip_block(s, MARK1)
s = strip_block(s, MARK2)

if MARKB in s:
    print("[OK] already V2B"); raise SystemExit(0)

inject = """
# === VSP_EXPORT_ZIP_P0_V2B ===
from flask import send_file, request
import json as _json
import time as _time
import zipfile as _zipfile
from pathlib import Path as _Path

def _vsp_export_pick_files_p0_v2b(run_dir: _Path):
    \"\"\"Commercial allowlist (best-effort): collect key artifacts without huge raws.\"\"\"
    picks = []

    # top-level common files
    top_names = [
        "SUMMARY.txt",
        "run_gate.json",
        "run_gate_summary.json",
        "run_manifest.json",
        "run_evidence_index.json",
        "verdict_4t.json",
        "nurl_audit_latest.json",
        "findings_unified.json",
        "findings_unified.csv",
        "findings_unified.sarif",
    ]
    for name in top_names:
        p = run_dir / name
        if p.is_file():
            picks.append((p, name))

    # small tool summaries
    try:
        for p in run_dir.glob("*_summary.json"):
            if p.is_file():
                picks.append((p, p.name))
    except Exception:
        pass

    # reports / report standard names
    for base in [run_dir / "reports", run_dir / "report"]:
        if base.is_dir():
            for name in ["findings_unified.json","findings_unified.csv","findings_unified.sarif","index.html","report.html"]:
                p = base / name
                if p.is_file():
                    picks.append((p, f\"{base.name}/{name}\"))

    # any nested findings_unified.json (guard size)
    try:
        for p in run_dir.rglob("findings_unified.json"):
            if p.is_file():
                try:
                    if p.stat().st_size > 50_000_000:
                        continue
                except Exception:
                    pass
                arc = str(p.relative_to(run_dir))
                picks.append((p, arc))
    except Exception:
        pass

    # de-dup by arcname
    seen=set()
    out=[]
    for src, arc in picks:
        if arc in seen:
            continue
        seen.add(arc)
        out.append((src, arc))
    return out

@app.get("/api/vsp/export_zip")
def vsp_export_zip_p0_v2b():
    run_id = (request.args.get("run_id") or "").strip()
    if not run_id:
        return jsonify({"ok": False, "error": "missing run_id"}), 400

    ui_dir = _Path(__file__).resolve().parent
    sb = ui_dir.parent
    out_dir = sb / "out"
    run_dir = out_dir / run_id
    if not run_dir.is_dir():
        return jsonify({"ok": False, "error": "run_id not found", "run_dir": str(run_dir)}), 404

    exp_dir = ui_dir / "out_ci" / "exports"
    exp_dir.mkdir(parents=True, exist_ok=True)
    ts = _time.strftime("%Y%m%d_%H%M%S")
    zip_path = exp_dir / f"VSP_EXPORT_{run_id}_{ts}.zip"

    # selfcheck snapshot (best-effort)
    try:
        sc = selfcheck_p0().get_json()  # type: ignore
    except Exception as e:
        sc = {"ok": False, "error": f"selfcheck snapshot failed: {e}"}

    # findings fallback: include UI unified payload if run has none
    fallback_findings = None
    try:
        fallback_findings = _vsp_load_findings_unified_p0_v1()  # type: ignore
    except Exception:
        fallback_findings = None

    picks = _vsp_export_pick_files_p0_v2b(run_dir)

    with _zipfile.ZipFile(zip_path, "w", compression=_zipfile.ZIP_DEFLATED) as zf:
        man = {
            "ok": True,
            "run_id": run_id,
            "run_dir": str(run_dir),
            "generated_at": ts,
            "picked_files": [arc for _, arc in picks],
        }
        zf.writestr("MANIFEST.json", _json.dumps(man, indent=2, ensure_ascii=False) + "\\n")
        zf.writestr("AUDIT/selfcheck_p0_snapshot.json", _json.dumps(sc, indent=2, ensure_ascii=False) + "\\n")

        for src, arc in picks:
            try:
                zf.write(str(src), arc)
            except Exception:
                pass

        has_findings = any(arc.endswith("findings_unified.json") for _, arc in picks)
        if (not has_findings) and isinstance(fallback_findings, dict):
            try:
                zf.writestr("findings_unified.json", _json.dumps(fallback_findings, indent=2, ensure_ascii=False) + "\\n")
            except Exception:
                pass

    return send_file(str(zip_path), as_attachment=True, download_name=zip_path.name, mimetype="application/zip")
# === /VSP_EXPORT_ZIP_P0_V2B ===
"""

mm = re.search(r"^if\s+__name__\s*==\s*['\"]__main__['\"]\s*:", s, flags=re.M)
if mm:
    s = s[:mm.start()] + "\n" + inject + "\n" + s[mm.start():]
else:
    s = s.rstrip() + "\n" + inject + "\n"

APP.write_text(s, encoding="utf-8")
print("[OK] injected VSP_EXPORT_ZIP_P0_V2B")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "[NEXT] restart 8910 then retest export:"
echo "  pkill -f 'gunicorn .*8910' 2>/dev/null || true; sleep 0.8"
echo "  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \\"
echo "    --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \\"
echo "    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \\"
echo "    --bind 127.0.0.1:8910 --pid out_ci/ui_8910.pid \\"
echo "    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \\"
echo "    > out_ci/ui_8910.boot.log 2>&1 &"
