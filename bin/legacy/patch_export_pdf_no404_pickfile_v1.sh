#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_exportpdf_no404_${TS}"
echo "[BACKUP] $F.bak_exportpdf_no404_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_EXPORT_PDF_NO404_PICKFILE_V1 ==="
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# Replace the pdf branch body between:
#   elif fmt == "pdf":
# and before the next:
#   if fmt == "pdf":  mt = "application/pdf"
pat = re.compile(
    r"(elif\s+fmt\s*==\s*['\"]pdf['\"]\s*:\s*\n)(.*?)(\n\s*if\s+fmt\s*==\s*['\"]pdf['\"]\s*:\s*mt\s*=\s*['\"]application/pdf['\"]\s*\n)",
    re.S
)
m = pat.search(t)
if not m:
    print("[ERR] cannot locate pdf branch block to patch (pattern not found)")
    raise SystemExit(1)

head = m.group(1)
tail = m.group(3)

new_body = f"""\
        {TAG}
        # Commercial behavior:
        # - Never return 404 for pdf export
        # - If pdf exists => send newest + X-VSP-EXPORT-AVAILABLE: 1
        # - If not => 200 empty body + X-VSP-EXPORT-AVAILABLE: 0
        files = []
        globs = [
            os.path.join(run_dir, "report*.pdf"),
            os.path.join(run_dir, "reports", "report*.pdf"),
            os.path.join(run_dir, "*.pdf"),
            os.path.join(run_dir, "reports", "*.pdf"),
        ]
        for g in globs:
            try:
                files += glob.glob(g)
            except Exception:
                pass

        files = sorted({f for f in files if isinstance(f, str) and os.path.isfile(f)})

        if not files:
            # keep endpoint alive (commercial), but mark unavailable
            return ("", 200, {{
                "X-VSP-EXPORT-AVAILABLE": "0",
                "Content-Type": "application/pdf",
            }})

        # pick newest file
        try:
            pick = max(files, key=lambda x: os.path.getmtime(x))
        except Exception:
            pick = files[-1]

        rsp = send_file(pick, mimetype="application/pdf", as_attachment=True, download_name=os.path.basename(pick))
        rsp.headers["X-VSP-EXPORT-AVAILABLE"] = "1"
        return rsp
"""

t2 = t[:m.start()] + head + new_body + tail + t[m.end():]
p.write_text(t2, encoding="utf-8")
print("[OK] patched pdf export branch: no404 + pickfile")
PY

python3 -m py_compile vsp_demo_app.py && echo "[OK] py_compile OK"

echo
echo "== restart 8910 (best effort) =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service 2>/dev/null | grep -q "vsp-ui-8910"; then
  sudo systemctl restart vsp-ui-8910.service || true
else
  # fallback: kill gunicorn on 8910 then restart using your usual script if exists
  fuser -k 8910/tcp 2>/dev/null || true
  if [ -x bin/restart_8910_gunicorn_commercial_v5.sh ]; then
    bin/restart_8910_gunicorn_commercial_v5.sh
  else
    echo "[WARN] no restart script found; please restart gunicorn manually"
  fi
fi

echo
echo "[DONE] patch_export_pdf_no404_pickfile_v1"
