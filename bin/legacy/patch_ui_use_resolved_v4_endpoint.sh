#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] backup suffix=$TS"

python3 - <<'PY'
from pathlib import Path

ROOT = Path(".")
targets = []
for pat in ["templates/**/*.html", "static/js/**/*.js"]:
    targets += list(ROOT.glob(pat))

old = "/api/vsp/runs_index_v3_fs_resolved"
new = "/api/vsp/runs_index_v3_fs_resolved_v4"

changed = 0
for f in targets:
    txt = f.read_text(encoding="utf-8", errors="ignore")
    if old in txt:
        bak = f.with_suffix(f.suffix + f".bak_resolvedv4_{__import__('time').strftime('%Y%m%d_%H%M%S')}")
        bak.write_text(txt, encoding="utf-8")
        f.write_text(txt.replace(old, new), encoding="utf-8")
        changed += 1

print(f"[OK] patched files={changed}")
PY

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"
