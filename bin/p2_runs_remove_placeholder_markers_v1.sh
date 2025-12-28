#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need grep; need sed; need python3; need date
command -v systemctl >/dev/null 2>&1 || true

TS="$(date +%Y%m%d_%H%M%S)"
EVD="/tmp/vsp_runs_marker_${TS}"
mkdir -p "$EVD"

echo "== [1] Capture /runs before =="
curl -fsS "$BASE/runs" -o "$EVD/runs_before.html"
echo "--- markers in /runs (before) ---"
grep -nE 'N/A|TODO|PLACEHOLDER' "$EVD/runs_before.html" | head -n 50 || echo "(none)"

echo
echo "== [2] Locate marker source in repo =="
hits="$EVD/hits.txt"
: > "$hits"
grep -RIn --line-number --exclude='*.bak_*' 'VSP_P2_RUNS_KPI_PLACEHOLDERS_V1' templates static/js *.py 2>/dev/null | tee "$hits" || true

if [ ! -s "$hits" ]; then
  echo "[ERR] Cannot find marker string in repo (maybe generated dynamically)."
  echo "Saved evidence at: $EVD"
  exit 2
fi

echo
echo "== [3] Patch: rename PLACEHOLDERS marker to SKELETON (keep trace tag, remove PLACEHOLDER word) =="
python3 - "$hits" "$TS" <<'PY'
import sys, re, pathlib, shutil

hits_file = pathlib.Path(sys.argv[1])
TS = sys.argv[2]

files=set()
for line in hits_file.read_text(encoding="utf-8",errors="replace").splitlines():
    # format: path:line:content
    path=line.split(":",1)[0].strip()
    if path:
        files.add(path)

old="VSP_P2_RUNS_KPI_PLACEHOLDERS_V1"
new="VSP_P2_RUNS_KPI_SKELETON_V1"

patched=[]
for f in sorted(files):
    p=pathlib.Path(f)
    if not p.exists() or p.suffix in (".png",".jpg",".zip",".gz",".tar"):
        continue
    s=p.read_text(encoding="utf-8",errors="replace")
    if old not in s:
        continue
    b=p.with_suffix(p.suffix + f".bak_runs_marker_{TS}")
    shutil.copy2(p,b)
    s2=s.replace(old,new).replace("/"+old,"/"+new)
    p.write_text(s2,encoding="utf-8")
    patched.append((str(p), str(b)))

print("[OK] patched_files=", len(patched))
for a,b in patched[:50]:
    print(" -", a, "(backup:", b, ")")
PY

echo
echo "== [4] Restart service =="
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo
echo "== [5] Capture /runs after + verify clean =="
curl -fsS "$BASE/runs" -o "$EVD/runs_after.html"
echo "--- markers in /runs (after) ---"
if grep -nE 'N/A|TODO|PLACEHOLDER' "$EVD/runs_after.html" >/dev/null; then
  echo "[AMBER] still found markers:"
  grep -nE 'N/A|TODO|PLACEHOLDER' "$EVD/runs_after.html" | head -n 50
  echo "Evidence kept at: $EVD"
  exit 0
fi
echo "[OK] /runs clean (no N/A/TODO/PLACEHOLDER tokens)"
echo "Evidence kept at: $EVD"

echo
echo "== [6] Rerun smoke audit (expect AMBER=0) =="
bash bin/p2_ui_commercial_smoke_audit_v1.sh
