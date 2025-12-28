#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
DIR="/etc/systemd/system/${SVC}.d"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need sudo
need python3
need systemctl
command -v systemd-analyze >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v ss >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -d "$DIR" ] || { echo "[ERR] missing $DIR"; exit 2; }

echo "== [1] sanitize ALL drop-ins: comment any line starting with '[' that isn't EXACTLY [Unit]/[Service]/[Install] =="
sudo python3 - <<'PY'
import glob, os, shutil

svc=os.environ.get("SVC","vsp-ui-8910.service")
dirp=f"/etc/systemd/system/{svc}.d"
ts=os.environ.get("TS","")
good={"[Unit]","[Service]","[Install]"}

cleaned=[]
for path in sorted(glob.glob(os.path.join(dirp,"*.conf"))):
    with open(path,"r",encoding="utf-8",errors="replace") as f:
        lines=f.read().splitlines(True)

    out=[]
    changed=False
    for ln in lines:
        s=ln.strip()
        # comment any junk section header-like lines that start with '[' but aren't strict good headers
        if s.startswith("[") and s not in good:
            out.append("# P3K26_V23B_BAD_HEADER_STRIPPED: " + ln)
            changed=True
        else:
            out.append(ln)

    if changed:
        bak=f"{path}.bak_v23b_{ts}"
        shutil.copy2(path,bak)
        with open(path,"w",encoding="utf-8") as f:
            f.write("".join(out))
        cleaned.append((os.path.basename(path), os.path.basename(bak)))

print("[OK] cleaned_files=", len(cleaned))
for a,b in cleaned[:50]:
    print(" -", a, "(backup:", b+")")
PY

echo "== [2] daemon-reload + verify =="
sudo systemctl daemon-reload
sudo systemctl reset-failed "$SVC" || true

if command -v systemd-analyze >/dev/null 2>&1; then
  systemd-analyze verify "/etc/systemd/system/${SVC}" 2>&1 | tail -n 120 || true
fi

echo "== [3] restart service =="
sudo systemctl restart "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
sudo systemctl status "$SVC" -n 30 --no-pager || true

echo "== [4] quick listen + smoke =="
ss -lptn "sport = :8910" || true
curl -fsS --connect-timeout 1 --max-time 5 "http://127.0.0.1:8910/api/vsp/rid_latest" | head -c 220; echo || true

echo "[DONE] v23b clean drop-ins"
