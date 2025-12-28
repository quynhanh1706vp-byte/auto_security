#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_exportzip_${TS}"
echo "[BACKUP] ${APP}.bak_exportzip_${TS}"

python3 - <<'PY'
import re, json, io, zipfile, time
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_EXPORT_ZIP_P0_V1"
if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

inject = f"""

# === {MARK} ===
from flask import send_file, request

@app.get("/api/vsp/export_zip")
def vsp_export_zip_p0_v1():
    \"\"\"Create a boss-ready ZIP for a run_id (safe, read-only, degrade-graceful).\"\"\"
    run_id = (request.args.get("run_id") or "").strip()
    if not run_id:
        return jsonify({{"ok": False, "error": "missing run_id"}}), 400

    ui_dir = Path(__file__).resolve().parent
    sb = ui_dir.parent
    out_dir = sb / "out"
    run_dir = out_dir / run_id

    if not run_dir.is_dir():
        return jsonify({{"ok": False, "error": "run_id not found", "run_dir": str(run_dir)}}), 404

    exp_dir = ui_dir / "out_ci" / "exports"
    exp_dir.mkdir(parents=True, exist_ok=True)

    ts = time.strftime("%Y%m%d_%H%M%S")
    zip_path = exp_dir / f"VSP_EXPORT_{{run_id}}_{{ts}}.zip"

    def add_if(zf, src: Path, arc: str):
        try:
            if src.is_file():
                zf.write(src, arc)
        except Exception:
            pass

    # gather common artifacts (best-effort)
    candidates = [
        ("SUMMARY.txt", run_dir / "SUMMARY.txt"),
        ("run_gate_summary.json", run_dir / "run_gate_summary.json"),
        ("findings_unified.json", run_dir / "reports" / "findings_unified.json"),
        ("findings_unified.csv",  run_dir / "reports" / "findings_unified.csv"),
        ("findings_unified.sarif",run_dir / "reports" / "findings_unified.sarif"),
        ("findings_unified.json", run_dir / "findings_unified.json"),
        ("findings_unified.csv",  run_dir / "findings_unified.csv"),
        ("findings_unified.sarif",run_dir / "findings_unified.sarif"),
        ("report/index.html",     run_dir / "report" / "index.html"),
        ("reports/index.html",    run_dir / "reports" / "index.html"),
    ]

    # snapshot selfcheck (live)
    try:
        sc = None
        try:
            sc = selfcheck_p0().get_json()  # type: ignore
        except Exception:
            sc = {{}}
        sc_bytes = (json.dumps(sc, indent=2, ensure_ascii=False) + "\\n").encode("utf-8", "replace")
    except Exception:
        sc_bytes = b'{{"ok":false,"error":"selfcheck snapshot failed"}}\\n'

    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        # always include manifest
        man = {{
            "ok": True,
            "run_id": run_id,
            "run_dir": str(run_dir),
            "generated_at": ts,
        }}
        zf.writestr("MANIFEST.json", json.dumps(man, indent=2, ensure_ascii=False) + "\\n")
        zf.writestr("AUDIT/selfcheck_p0_snapshot.json", sc_bytes)

        for arc, src in candidates:
            add_if(zf, src, arc)

    return send_file(str(zip_path), as_attachment=True, download_name=zip_path.name, mimetype="application/zip")
# === /{MARK} ===
"""

mm = re.search(r"^if\s+__name__\s*==\s*['\\\"]__main__['\\\"]\s*:", s, flags=re.M)
if mm:
    s = s[:mm.start()] + inject + "\n" + s[mm.start():]
else:
    s = s.rstrip() + "\n" + inject + "\n"

p.write_text(s, encoding="utf-8")
print("[OK] injected /api/vsp/export_zip into vsp_demo_app.py")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"
echo "[NEXT] restart 8910 then test:"
echo "  curl -sS 'http://127.0.0.1:8910/api/vsp/runs?limit=5' | jq '.items[0].run_id' -r"
echo "  curl -OJ 'http://127.0.0.1:8910/api/vsp/export_zip?run_id=RUN_ID_HERE'"
