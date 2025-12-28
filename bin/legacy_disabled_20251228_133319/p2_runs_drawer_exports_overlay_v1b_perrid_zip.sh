#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need node; need grep
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

JS="static/js/vsp_runs_kpi_compact_v3.js"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_runsexport_perrid_${TS}"
echo "[BACKUP] ${JS}.bak_runsexport_perrid_${TS}"

python3 - "$JS" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

marker="VSP_P2_RUNS_DRAWER_EXPORTS_OVERLAY_V1B_PERRID_ZIP"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# We patch inside the exports block by inserting zipPaths + resolving per-rid zipPath before release_latest zipUrl.
# Find a stable anchor: the definition of htmlPaths/pdfPaths in the exports addon.
anchor = "    const htmlPaths=["
i = s.find(anchor)
if i < 0:
    print("[ERR] cannot find exports block anchor (htmlPaths)")
    raise SystemExit(2)

insert = (
    "    const zipPaths=[\n"
    "      \"reports/report.zip\",\n"
    "      \"reports/reports.zip\",\n"
    "      \"reports/run_artifacts.zip\",\n"
    "      \"reports/artifacts.zip\",\n"
    "      \"report/report.zip\",\n"
    "      \"report/reports.zip\",\n"
    "      \"run_artifacts.zip\",\n"
    "      \"artifacts.zip\",\n"
    "      \"package.zip\",\n"
    "      \"bundle.zip\"\n"
    "    ];\n\n"
)

# Insert zipPaths once (near htmlPaths)
if "const zipPaths" not in s[i-400:i+50]:
    s = s[:i] + insert + s[i:]

# Now patch the zip button logic: find block where zipUrl is set from release_latest then zipBtn.onclick uses zipUrl
# We'll inject per-rid zipPath check before using release_latest.
pat = r'(const zipUrl\s*=\s*\(rel\.ok[\s\S]{0,200}?download_url[\s\S]{0,200}?\)\s*\?\s*rel\.json\.download_url\s*:\s*null;\s*\n\s*const zipBtn=box\.querySelector\(\x27\[data-testid="runs-exp-zip"\]\x27\);)'
m = re.search(pat, s)
if not m:
    # fallback: simpler pattern
    pat2 = r'(const zipUrl\s*=\s*[\s\S]{0,200}?download_url[\s\S]{0,200}?;[\s\S]{0,120}?const zipBtn=box\.querySelector\(\x27\[data-testid="runs-exp-zip"\]\x27\);)'
    m = re.search(pat2, s)
if not m:
    print("[ERR] cannot locate zipUrl/zipBtn block in exports addon")
    raise SystemExit(2)

inject = (
    m.group(1)
    + "\n\n    // Prefer per-RID ZIP if available\n"
      "    const ridZipPath = await pickFile(rid, zipPaths);\n"
      "    const ridZipUrl = ridZipPath ? (`/api/vsp/run_file_allow?rid=${encodeURIComponent(rid)}&path=${encodeURIComponent(ridZipPath)}&limit=200000`) : null;\n"
)

s = s[:m.start(1)] + inject + s[m.end(1):]

# Patch zipBtn onclick to use ridZipUrl first then zipUrl
# Find "zipBtn.onclick=()=>{ if(zipUrl) window.open(zipUrl"
s = re.sub(
    r'zipBtn\.onclick=\(\)=>\{\s*if\(zipUrl\)\s*window\.open\(zipUrl, "_blank", "noopener"\);\s*\};',
    'zipBtn.onclick=()=>{\n      const u = ridZipUrl || zipUrl;\n      if(u) window.open(u, "_blank", "noopener");\n    };',
    s, count=1
)

# Patch hint line to include rid zip status
s = re.sub(
    r'hint\.textContent\s*=\s*`ZIP:\$\{zipUrl\?\s*"OK":"—"\} · HTML:',
    'hint.textContent = `ZIP:${ridZipUrl? "RID":"—"}${(!ridZipUrl && zipUrl)? "(fallback)":""} · HTML:',
    s, count=1
)

s += f"\n/* {marker} */\n"
p.write_text(s, encoding="utf-8")
print("[OK] patched exports: per-RID zip first")
PY

node -c "$JS"
echo "[OK] node -c OK"
if systemctl is-active --quiet "$SVC" 2>/dev/null; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
fi

echo "== verify marker in served JS =="
curl -fsS "$BASE/static/js/$(basename "$JS")" | grep -n "VSP_P2_RUNS_DRAWER_EXPORTS_OVERLAY_V1B_PERRID_ZIP" | head -n 2
