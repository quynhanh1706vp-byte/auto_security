#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportv3fs_${TS}"
echo "[BACKUP] $F.bak_exportv3fs_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
t=p.read_text(encoding="utf-8", errors="ignore")

# Ensure imports exist
need_imports = [
  ("from flask import", ["send_file", "request", "jsonify"]),
]
for anchor, names in need_imports:
    if anchor in t:
        # add missing names into existing import line(s) if needed
        # simplest: inject a new import line if send_file not mentioned anywhere
        if "send_file" not in t or "request" not in t or "jsonify" not in t:
            t = re.sub(r"(from flask import[^\n]+)\n",
                       lambda m: m.group(1) + ", send_file, request, jsonify\n" if "send_file" not in m.group(1) else m.group(0),
                       t, count=1)
    else:
        # insert near top
        t = "from flask import send_file, request, jsonify\n" + t

# If route already patched, skip
TAG = "# === VSP_EXPORT_V3_FORCE_FS_V1 ==="
if TAG not in t:
    block = r'''
# === VSP_EXPORT_V3_FORCE_FS_V1 ===
@app.route("/api/vsp/run_export_v3/<rid>")
def api_vsp_run_export_v3_force_fs(rid):
    """
    Force filesystem export: resolve ci_run_dir via local run_status_v2, then serve export file.
    This avoids JSON fallback when exporter is disabled/miswired.
    """
    fmt = (request.args.get("fmt") or "html").strip().lower()
    # Resolve ci_run_dir via local API (no external deps)
    ci_dir = None
    try:
        import urllib.request, json
        u = f"http://127.0.0.1:8910/api/vsp/run_status_v2/{rid}"
        with urllib.request.urlopen(u, timeout=2) as resp:
            data = json.loads(resp.read().decode("utf-8", errors="ignore"))
            if isinstance(data, dict):
                ci_dir = data.get("ci_run_dir") or data.get("ci") or data.get("run_dir")
    except Exception:
        ci_dir = None

    if not ci_dir:
        r = jsonify({"ok": False, "error": "ci_run_dir_not_found", "rid": rid, "fmt": fmt})
        r.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return r, 200

    from pathlib import Path
    run_dir = Path(ci_dir)

    # Candidate export filenames (commercial layouts)
    if fmt == "html":
        cands = [
            run_dir/"reports"/"vsp_export.html",
            run_dir/"reports"/"report_commercial.html",
            run_dir/"reports"/"report_cio.html",
            run_dir/"reports"/"commercial.html",
        ]
        mime = "text/html"
        dlname = "vsp_export.html"
    elif fmt == "pdf":
        cands = [
            run_dir/"reports"/"vsp_export.pdf",
            run_dir/"reports"/"report_commercial.pdf",
            run_dir/"reports"/"report_cio.pdf",
            run_dir/"reports"/"commercial.pdf",
            run_dir/"vsp_export.pdf",
        ]
        mime = "application/pdf"
        dlname = "vsp_export.pdf"
    elif fmt == "zip":
        cands = [
            run_dir/"reports"/"vsp_export.zip",
            run_dir/"reports"/"export.zip",
            run_dir/"vsp_export.zip",
        ]
        mime = "application/zip"
        dlname = "vsp_export.zip"
    else:
        r = jsonify({"ok": False, "error": "bad_fmt", "fmt": fmt})
        r.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return r, 200

    pick = None
    for fp in cands:
        try:
            if fp.is_file() and fp.stat().st_size > 0:
                pick = fp
                break
        except Exception:
            continue

    if not pick:
        r = jsonify({"ok": False, "error": "export_file_not_found", "rid": rid, "fmt": fmt, "searched": [str(x) for x in cands]})
        r.headers["X-VSP-EXPORT-AVAILABLE"] = "0"
        return r, 200

    resp = send_file(str(pick), mimetype=mime, as_attachment=True, download_name=dlname, conditional=True)
    resp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
    return resp
'''
    # Insert near end (before if __name__ == "__main__" if exists)
    m = re.search(r"if\s+__name__\s*==\s*[\"']__main__[\"']\s*:", t)
    if m:
        t = t[:m.start()] + block + "\n\n" + t[m.start():]
    else:
        t = t + "\n\n" + block

p.write_text(t, encoding="utf-8")
print("[OK] inserted forced /api/vsp/run_export_v3/<rid> filesystem export route")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "[DONE] restart 8910:"
/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
