#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# Only patch the real UI server files (avoid release logs / random matches)
CAND=("vsp_demo_app.py" "wsgi_vsp_ui_gateway.py")
TARGET=""
for f in "${CAND[@]}"; do
  [ -f "$f" ] || continue
  if grep -q "run_file_allow" "$f"; then
    TARGET="$f"; break
  fi
done
[ -n "$TARGET" ] || { echo "[ERR] cannot find run_file_allow in vsp_demo_app.py / wsgi_vsp_ui_gateway.py"; exit 2; }

cp -f "$TARGET" "${TARGET}.bak_allow_gate_reports_${TS}"
echo "[BACKUP] ${TARGET}.bak_allow_gate_reports_${TS}"
echo "[INFO] patch target: $TARGET"

python3 - <<'PY'
from pathlib import Path
import re, sys, time

p = Path(sys.argv[1]) if len(sys.argv) > 1 else None
# pass via argv from bash
PY
python3 - "$TARGET" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_ALLOW_GATE_REPORTS_V2"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

# We know 403 response contains allowlist with "reports/findings_unified.csv"
# Insert our gate paths next to that anchor, if not already present.
add = ['"reports/run_gate_summary.json"', '"reports/run_gate.json"']

if any(a.strip('"') in s for a in add):
    # still add marker (idempotent)
    s = s + f"\n\n# {marker}\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] gate paths already present; marker appended")
    sys.exit(0)

anchor_patterns = [
    r'("reports/findings_unified\.csv"\s*,?)',
    r"('reports/findings_unified\.csv'\s*,?)",
]

inserted = False
for ap in anchor_patterns:
    m = re.search(ap, s)
    if not m:
        continue
    ins = m.group(1)
    # keep same quote style as anchor
    if ins.startswith("'"):
        add2 = ["'reports/run_gate_summary.json'", "'reports/run_gate.json'"]
    else:
        add2 = ['"reports/run_gate_summary.json"', '"reports/run_gate.json"']

    # insert right AFTER anchor line
    repl = ins + "\n      " + add2[0] + ",\n      " + add2[1] + ","
    s2, n = re.subn(ap, repl, s, count=1)
    if n == 1:
        s = s2
        inserted = True
        break

if not inserted:
    # fallback: append into an allow list block if we can find a literal "allow":[ ... ]
    # (best-effort, still safe)
    s = s + "\n# " + marker + " (fallback append; please manually place into allowlist if needed)\n"
    s = s + "# add allow: reports/run_gate_summary.json, reports/run_gate.json\n"
    p.write_text(s, encoding="utf-8")
    print("[WARN] could not find anchor 'reports/findings_unified.csv' to inject; appended fallback comment only")
    sys.exit(0)

s += f"\n\n# {marker}\n"
p.write_text(s, encoding="utf-8")
print("[OK] injected allow entries for reports/run_gate_summary.json + reports/run_gate.json")
PY

python3 -m py_compile "$TARGET" >/dev/null
echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== smoke: /api/vsp/runs?limit=1 =="
curl -fsS "$BASE/api/vsp/runs?limit=1" | head -c 240; echo

echo "== verify (should be 200, not 403) =="
RID="${1:-RUN_khach6_FULL_20251129_133030}"
for pth in "reports/run_gate_summary.json" "reports/run_gate.json"; do
  echo "-- $pth"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$pth" || true
  grep -iE 'HTTP/|Content-Type|X-VSP-Fallback-Path' /tmp/h | sed 's/\r$//'
  head -c 160 /tmp/b; echo; echo
done

echo "[DONE] Now HARD refresh /vsp5 (Ctrl+Shift+R). GateStory should stop falling back to last-good."
