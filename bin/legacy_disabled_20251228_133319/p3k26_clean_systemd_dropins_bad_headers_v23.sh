#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
DIR="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need python3
need systemctl
command -v grep >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true

[ -d "$DIR" ] || { echo "[ERR] missing $DIR"; exit 2; }

echo "== [1] scan & clean bad section headers in drop-ins =="
sudo python3 - <<'PY'
import os, re, shutil, time, glob

svc=os.environ.get("SVC","vsp-ui-8910.service")
dirp=f"/etc/systemd/system/{svc}.d"
ts=os.environ.get("TS")

good_sections={"[Unit]","[Service]","[Install]"}
bad_files=[]

for path in sorted(glob.glob(os.path.join(dirp,"*.conf"))):
    with open(path,"r",encoding="utf-8",errors="replace") as f:
        lines=f.read().splitlines(True)
    changed=False
    out=[]
    for ln in lines:
        s=ln.strip()
        # detect INI section headers that are not standard ones
        if s.startswith("[") and s.endswith("]") and s not in good_sections:
            out.append("# P3K26_V23_COMMENT_BAD_HEADER: " + ln)
            changed=True
        else:
            out.append(ln)
    if changed:
        bak=f"{path}.bak_v23_{ts}"
        shutil.copy2(path,bak)
        with open(path,"w",encoding="utf-8") as f:
            f.write("".join(out))
        bad_files.append((os.path.basename(path), os.path.basename(bak)))

print("[OK] cleaned_files=", len(bad_files))
for a,b in bad_files[:50]:
    print(" -",a,"(backup:",b+")")
PY

echo "== [2] daemon-reload + verify =="
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SVC" || true

# show if still bad
sudo systemctl status "$SVC" -n 15 --no-pager || true
echo "== [3] verify drop-in parse =="
systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 80 || true

echo "[DONE] v23 clean drop-ins"
