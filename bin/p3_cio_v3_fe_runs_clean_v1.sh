#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] Find JS hits =="
grep -RIn --line-number '/api/vsp/run_file_allow|/api/vsp/runs\?limit=1|findings_unified\.json|run_gate_summary\.json' static/js | head -n 120 || true
echo

python3 - <<'PY'
from pathlib import Path
import re, time

ts = time.strftime("%Y%m%d_%H%M%S")
root = Path("static/js")
hits=[]
for f in root.glob("*.js"):
    s=f.read_text(encoding="utf-8", errors="replace")
    if ("/api/vsp/run_file_allow" in s) or ("/api/vsp/runs?limit=1" in s) or ("findings_unified.json" in s) or ("run_gate_summary.json" in s):
        hits.append(f)

print("[INFO] patch_files =", len(hits))
for f in hits:
    s=f.read_text(encoding="utf-8", errors="replace")
    orig=s
    # 1) latest: never use runs?limit=1 for canonical latest
    s=s.replace("/api/vsp/runs?limit=1", "/api/vsp/rid_latest_v3")

    # 2) hardcoded plumbing strings in UI text
    for leak in ["findings_unified.json","reports/findings_unified.json","run_gate_summary.json","reports/run_gate_summary.json"]:
        s=s.replace(leak,"")

    # 3) run_file_allow -> artifact_v3 / findings_v3 / run_gate_v3
    # - gate fetch
    s=re.sub(r'/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=run_gate_summary\.json',
             '/api/vsp/run_gate_v3?rid=${encodeURIComponent(rid)}', s)

    # - findings JSON file fetch -> findings_v3 (page mode)
    s=re.sub(r'/api/vsp/run_file_allow\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*findings[^)]*\)\}&limit=\d+',
             '/api/vsp/findings_v3?rid=${encodeURIComponent(rid)}&limit=500&offset=0', s)

    # - download/open artifacts: map to artifact_v3 kind
    # If code kept variables like pdfPath/htmlPath/zipPath/tgzPath/csvPath, we force kind-based.
    s=s.replace("/api/vsp/run_file_allow", "/api/vsp/artifact_v3")

    # best-effort: whenever FE passes &path=...pdf -> kind=pdf
    s=re.sub(r'(/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*pdf[^)]*\)\}[^"\']*)',
             '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=pdf&download=1', s)
    s=re.sub(r'(/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*html[^)]*\)\}[^"\']*)',
             '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=html&download=1', s)
    s=re.sub(r'(/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*csv[^)]*\)\}[^"\']*)',
             '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=csv&download=1', s)
    s=re.sub(r'(/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*tgz[^)]*\)\}[^"\']*)',
             '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=tgz&download=1', s)
    s=re.sub(r'(/api/vsp/artifact_v3\?rid=\$\{encodeURIComponent\(rid\)\}&path=\$\{encodeURIComponent\([^)]*zip[^)]*\)\}[^"\']*)',
             '/api/vsp/artifact_v3?rid=${encodeURIComponent(rid)}&kind=zip&download=1', s)

    if s != orig:
        bak=f.with_name(f.name + f".bak_cio_v3fe_{ts}")
        bak.write_text(orig, encoding="utf-8")
        f.write_text(s, encoding="utf-8")
        print("[OK] patched", f.name)
PY

echo
echo "== [1] Post-check: ensure no run_file_allow remains =="
if grep -RIn --line-number '/api/vsp/run_file_allow' static/js >/dev/null; then
  echo "[WARN] still has run_file_allow:"
  grep -RIn --line-number '/api/vsp/run_file_allow' static/js | head -n 80
else
  echo "[OK] no run_file_allow in static/js"
fi

echo "[DONE] Hard refresh browser (Ctrl+Shift+R) then re-test /runs click-through."
