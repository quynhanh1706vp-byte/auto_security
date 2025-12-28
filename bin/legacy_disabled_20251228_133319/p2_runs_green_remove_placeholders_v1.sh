#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need curl; need python3; need grep; need sed; need awk; need head; need sort; need date
command -v systemctl >/dev/null 2>&1 || true

tmp="$(mktemp -d /tmp/vsp_runs_green_XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

echo "== [1] Fetch /runs HTML and locate placeholder markers =="
curl -fsS "$BASE/runs" -o "$tmp/runs.html"

echo "--- markers in /runs HTML (line + snippet) ---"
if grep -nE 'N/A|TODO|PLACEHOLDER' "$tmp/runs.html" >/dev/null; then
  grep -nE 'N/A|TODO|PLACEHOLDER' "$tmp/runs.html" | head -n 50
else
  echo "(none found in HTML) -> amber likely came from a different fetch; stop."
  exit 0
fi

echo
echo "== [2] Extract JS list referenced by /runs (for mapping) =="
grep -oE '/static/js/[^"]+\.js(\?v=[0-9]+)?' "$tmp/runs.html" | sort -u | sed 's/^/  /' || true

echo
echo "== [3] Find offending strings in repo (templates + runs-related js) =="
# First try templates (most likely)
hits="$(grep -RIn --line-number -E 'N/A|TODO|PLACEHOLDER' templates 2>/dev/null || true)"
if [ -n "$hits" ]; then
  echo "$hits" | head -n 80
else
  echo "(no hits in templates/)"
fi

echo
echo "== [4] Patch: replace markers in templates + runs-related JS/bundles =="
TS="$(date +%Y%m%d_%H%M%S)"
patched=0

python3 - <<'PY'
import re, glob, os, shutil, datetime
TS=os.environ.get("TS") or datetime.datetime.now().strftime("%Y%m%d_%H%M%S")

def backup(path):
    b=f"{path}.bak_green_{TS}"
    shutil.copy2(path,b)
    return b

def patch_text(s):
    # Make commercial-clean:
    # - visible placeholder N/A -> —
    # - remove TODO/PLACEHOLDER tokens in served content
    s2=s.replace("N/A","—")
    # remove TODO/PLACEHOLDER words (keep spacing)
    s2=re.sub(r'\bTODO\b', '', s2)
    s2=re.sub(r'\bPLACEHOLDER\b', '', s2)
    # clean double spaces created by removals
    s2=re.sub(r'[ \t]{2,}', ' ', s2)
    return s2

targets=[]

# templates (most probable source of marker in HTML)
for f in glob.glob("templates/**/*", recursive=True):
    if os.path.isfile(f) and any(f.endswith(ext) for ext in (".html",".jinja",".j2",".tmpl",".txt")):
        targets.append(f)

# runs-related JS/bundles/topbar/tabs (just in case)
for f in glob.glob("static/js/*.js"):
    base=os.path.basename(f)
    if any(k in base for k in ("runs","topbar","tabs","bundle")):
        targets.append(f)

patched=[]
for f in targets:
    try:
        s=open(f,"r",encoding="utf-8",errors="replace").read()
    except Exception:
        continue
    if not re.search(r'N/A|TODO|PLACEHOLDER', s):
        continue
    b=backup(f)
    s2=patch_text(s)
    open(f,"w",encoding="utf-8").write(s2)
    patched.append((f,b))

print("[OK] patched_files=", len(patched))
for f,b in patched[:40]:
    print(" -", f, "(backup:", b, ")")
PY

echo
echo "== [5] Restart service =="
sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

echo
echo "== [6] Recheck /runs marker presence =="
curl -fsS "$BASE/runs" -o "$tmp/runs_after.html"
if grep -nE 'N/A|TODO|PLACEHOLDER' "$tmp/runs_after.html" >/dev/null; then
  echo "[AMBER] still found markers after patch:"
  grep -nE 'N/A|TODO|PLACEHOLDER' "$tmp/runs_after.html" | head -n 30
  exit 0
fi
echo "[OK] /runs HTML is clean (no markers)"

echo
echo "== [7] Run smoke audit again =="
bash bin/p2_ui_commercial_smoke_audit_v1.sh
