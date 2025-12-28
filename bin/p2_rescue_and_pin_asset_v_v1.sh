#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need grep; need sed

# 1) restore latest good backup made by the broken script
bak="$(ls -1t ${W}.bak_assetv_stable_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] cannot find backup: ${W}.bak_assetv_stable_*"
  echo "      list existing backups:"
  ls -1 ${W}.bak_* 2>/dev/null | tail -n 30 || true
  exit 2
fi

cp -f "$bak" "$W"
echo "[OK] restored $W from $bak"

# 2) patch asset version expression safely (no top-of-file insertion)
python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_ASSET_V_ENV_FIRST_V1"
if marker in s:
    print("[OK] marker already present; skip")
    sys.exit(0)

# We only rewrite common patterns used for ?v= cache busting.
# Replace: int(time.time()) / str(int(time.time())) / f"{int(time.time())}" cases in asset-v context
# We avoid touching unrelated time.time() uses by requiring "asset" or "?v=" nearby in the same line.
stable_expr = '(os.environ.get("VSP_ASSET_V") or os.environ.get("VSP_P1_ASSET_V_RUNTIME_TS_V1") or os.environ.get("VSP_RELEASE_TS") or str(int(time.time())))'

lines=s.splitlines(True)
out=[]
changed=0
for line in lines:
    l=line
    if ("?v=" in l or "asset_v" in l or "assetv" in l or "ASSET_V" in l) and "time.time()" in l:
        # patch the most common shapes
        l2=re.sub(r'str\s*\(\s*int\s*\(\s*time\.time\s*\(\s*\)\s*\)\s*\)', stable_expr, l)
        l2=re.sub(r'int\s*\(\s*time\.time\s*\(\s*\)\s*\)', stable_expr, l2)
        if l2 != l:
            l=l2
            changed += 1
    out.append(l)

s2="".join(out)

# Ensure needed imports exist if we used os/time
# If file already has imports, do nothing; otherwise insert minimal imports near top (but safely).
if "os." in s2 and "import os" not in s2:
    # insert after first import block line we can find; keep indentation of that line
    m=re.search(r'(?m)^(?P<indent>\s*)(import|from)\s+[^\n]+', s2)
    if not m:
        # fallback: just prepend
        s2 = "import os\nimport time\n" + s2
    else:
        idx=m.start()
        indent=m.group("indent") or ""
        ins=f"{indent}import os\n{indent}import time\n"
        s2 = s2[:idx] + ins + s2[idx:]
        changed += 1

# stamp marker near end (comment only)
s2 += f"\n# {marker}: prefer env VSP_ASSET_V for stable cache busting\n"

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched asset v occurrences: {changed}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK: $W"

# 3) pin VSP_ASSET_V via systemd drop-in (persistent)
ASSET_V="$(date +%s)"
echo "[INFO] pin VSP_ASSET_V=$ASSET_V"

if command -v systemctl >/dev/null 2>&1; then
  sudo mkdir -p "/etc/systemd/system/${SVC}.d"
  sudo tee "/etc/systemd/system/${SVC}.d/p2_asset_v_pin.conf" >/dev/null <<EOF
[Service]
Environment=VSP_ASSET_V=${ASSET_V}
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; set env VSP_ASSET_V=$ASSET_V manually and restart service"
fi

# 4) quick verify v= is consistent across tabs
echo "== quick verify v= across tabs =="
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE 'v=[0-9]+' | head -n 8 || true
done

echo "[OK] done: asset_v pinned + wsgi compile clean"
