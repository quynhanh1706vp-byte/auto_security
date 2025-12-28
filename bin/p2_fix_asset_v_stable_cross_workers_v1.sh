#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_assetv_stable_${TS}"
echo "[BACKUP] ${W}.bak_assetv_stable_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_ASSET_V_STABLE_CROSS_WORKERS_V1"

if marker in s:
    print("[OK] marker already present; skip")
    raise SystemExit(0)

# Insert a stable ASSET_V block near the top (after imports best-effort)
ins = r'''
# --- %s ---
# Commercial: stable asset version for ALL templates/requests (avoid DUP ?v= across tabs/workers)
import os, time as _time
_VSP_ASSET_V = os.environ.get("VSP_ASSET_V")
if not _VSP_ASSET_V:
    # freeze once per process; good enough for commercial cache consistency
    _VSP_ASSET_V = str(int(_time.time()))
    os.environ["VSP_ASSET_V"] = _VSP_ASSET_V
# --- end %s ---
''' % (marker, marker)

# try to place after the first block of imports
m=re.search(r'(?s)\A(.*?\n)(\s*(?:from|import)\s+[^\n]+\n(?:\s*(?:from|import)\s+[^\n]+\n)*)', s)
if m:
    head=m.group(1)+m.group(2)
    rest=s[len(head):]
    s2=head+ins+rest
else:
    s2=ins+s

# ensure a context_processor provides asset_v (works for all templates)
if "context_processor" not in s2 or "asset_v" not in s2:
    # append near end (safe)
    s2 += r'''

# --- %s (template injection) ---
try:
    @app.context_processor
    def _vsp_inject_asset_v():
        return {"asset_v": os.environ.get("VSP_ASSET_V")}
except Exception:
    pass
# --- end %s ---
''' % (marker, marker)

p.write_text(s2, encoding="utf-8")
print("[OK] patched stable asset_v")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting: $SVC"
  sudo systemctl restart "$SVC"
  sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
else
  echo "[WARN] systemctl not found; restart manually"
fi

echo "== quick verify: fetch tabs and grep v= =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for pth in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "-- $pth --"
  curl -sS "$BASE$pth" | grep -oE 'v=[0-9]+' | head -n 5 || true
done
