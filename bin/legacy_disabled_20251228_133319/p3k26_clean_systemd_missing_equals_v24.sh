#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need python3
need systemctl
command -v systemd-analyze >/dev/null 2>&1 || true

F1="/etc/systemd/system/${SVC}.d/override.conf"
F2="/etc/systemd/system/${SVC}.d/zzzz-999-final.conf"

sudo python3 - <<'PY'
from pathlib import Path
import shutil, os, re

ts=os.environ.get("TS","")
files=[os.environ["F1"], os.environ["F2"]]

section_ok=re.compile(r'^\s*\[(Unit|Service|Install)\]\s*$')
kv_ok=re.compile(r'^\s*[A-Za-z0-9][A-Za-z0-9_]*\s*=')

for fp in files:
    p=Path(fp)
    if not p.exists():
        print("[SKIP] missing", fp)
        continue
    s=p.read_text(encoding="utf-8", errors="replace").splitlines(True)
    out=[]
    changed=False
    for ln in s:
        t=ln.strip()
        if t=="" or t.startswith("#") or section_ok.match(t) or kv_ok.match(t):
            out.append(ln); continue
        # everything else is suspicious -> comment
        out.append("# P3K26_V24_COMMENT_BAD_LINE: " + ln)
        changed=True
    if changed:
        bak=str(p)+f".bak_v24_{ts}"
        shutil.copy2(p,bak)
        p.write_text("".join(out), encoding="utf-8")
        print("[OK] cleaned", fp, "backup", bak)
    else:
        print("[OK] no bad lines in", fp)
PY

sudo systemctl daemon-reload
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== verify tail =="
if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 80 || true
fi
