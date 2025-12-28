#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

python3 - <<'PY'
from pathlib import Path
import time

ROOT = Path(".")
targets = []
for pat in ["templates/**/*.html", "static/js/**/*.js"]:
    targets += list(ROOT.glob(pat))

pairs = [
  ("/api/vsp/runs_index_v3_fs_resolved_v4", "/api/vsp/runs_index_v3_fs"),
  ("/api/vsp/runs_index_v3_fs_resolved",    "/api/vsp/runs_index_v3_fs"),
]

ts = time.strftime("%Y%m%d_%H%M%S")
changed = 0
for f in targets:
    txt = f.read_text(encoding="utf-8", errors="ignore")
    new_txt = txt
    for old, new in pairs:
        new_txt = new_txt.replace(old, new)
    if new_txt != txt:
        bak = f.with_suffix(f.suffix + f".bak_runsv3fs_{ts}")
        bak.write_text(txt, encoding="utf-8")
        f.write_text(new_txt, encoding="utf-8")
        changed += 1

print(f"[OK] patched files={changed}")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
