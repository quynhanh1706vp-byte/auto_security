#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep

F="templates/vsp_runs_reports_v1.html"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_testid_${TS}"
echo "[BACKUP] ${F}.bak_testid_${TS}"

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path
p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
orig=s
if 'data-testid="vsp-runs-main"' in s:
    print("[OK] already has testid")
    raise SystemExit(0)

# Try to tag the main container: first div with id vsp-runs-main OR first <main> OR body wrapper
s2=s
s2=re.sub(r'(<div\b[^>]*\bid="vsp-runs-main"[^>]*)(>)', r'\1 data-testid="vsp-runs-main"\2', s2, count=1, flags=re.I)
if s2==s:
    s2=re.sub(r'(<main\b)(>)', r'\1 data-testid="vsp-runs-main"\2', s2, count=1, flags=re.I)
if s2==s:
    s2=re.sub(r'(<body\b[^>]*)(>)', r'\1 data-testid="vsp-runs-main"\2', s2, count=1, flags=re.I)

p.write_text(s2, encoding="utf-8")
print("[OK] changed=", s2!=orig)
PY

echo "== verify =="
grep -n 'data-testid="vsp-runs-main"' "$F" | head -n 5 || true
