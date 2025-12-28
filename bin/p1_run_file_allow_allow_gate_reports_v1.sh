#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed

TS="$(date +%Y%m%d_%H%M%S)"

# locate python file that contains allowlist (look for findings_unified.csv or allow[] response)
PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "reports/findings_unified.csv" . 2>/dev/null | cut -d: -f1 || true)"
if [ -z "$PYF" ]; then
  PYF="$(grep -RIn --exclude='*.bak_*' --include='*.py' -m1 "\"allow\":\\s*\\[" . 2>/dev/null | cut -d: -f1 || true)"
fi
[ -n "$PYF" ] || { echo "[ERR] cannot locate python file for run_file_allow allowlist"; exit 2; }
[ -f "$PYF" ] || { echo "[ERR] missing $PYF"; exit 2; }

cp -f "$PYF" "${PYF}.bak_allow_gate_reports_${TS}"
echo "[BACKUP] ${PYF}.bak_allow_gate_reports_${TS}"
echo "[INFO] patch target: $PYF"

python3 - "$PYF" <<'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_RUN_FILE_ALLOW_GATE_REPORTS_ALLOW_V1"
if marker in s:
    print("[OK] already patched")
    sys.exit(0)

need_add = ["reports/run_gate_summary.json", "reports/run_gate.json"]
if all(x in s for x in need_add):
    s = s + "\n# " + marker + " (noop: already contains allow entries)\n"
    p.write_text(s, encoding="utf-8")
    print("[OK] allow entries already present; wrote marker")
    sys.exit(0)

# Heuristic: insert after line that contains reports/findings_unified.csv (best anchor)
lines = s.splitlines(True)

def insert_after_anchor(anchor_substr: str, to_insert: list[str]) -> bool:
    for i, ln in enumerate(lines):
        if anchor_substr in ln:
            # detect quote style and indentation
            indent = ln[:len(ln) - len(ln.lstrip())]
            q = "'" if "'" in ln else '"'
            ins = ""
            for item in to_insert:
                if item in s:
                    continue
                ins += f"{indent}{q}{item}{q},\n"
            if not ins:
                return False
            lines.insert(i+1, ins)
            return True
    return False

ok = insert_after_anchor("reports/findings_unified.csv", need_add)
if not ok:
    # fallback: insert after SUMMARY.txt if exists
    ok = insert_after_anchor("SUMMARY.txt", need_add)

if not ok:
    # last resort: append near end with a big comment (still works if allowlist is built dynamically elsewhere)
    append = "\n# " + marker + "\n# NOTE: could not find allowlist anchor; please add these to run_file_allow allowlist:\n"
    append += "\n".join([f"#  - {x}" for x in need_add]) + "\n"
    s2 = s + append
    p.write_text(s2, encoding="utf-8")
    print("[WARN] anchor not found; appended instructions + marker")
    sys.exit(0)

s2 = "".join(lines) + f"\n# {marker}\n"
p.write_text(s2, encoding="utf-8")
print("[OK] inserted allow entries:", need_add)
PY

echo "== py_compile =="
python3 -m py_compile "$PYF"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.6

echo "== verify: latest RID gate in reports =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json; j=json.load(sys.stdin); print((j.get('items') or [{}])[0].get('run_id',''))" 2>/dev/null || true)"
echo "[RID]=$RID"

for pth in "reports/run_gate_summary.json" "reports/run_gate.json"; do
  echo "---- $pth ----"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$pth" || echo "[curl rc=$?]"
  grep -iE 'HTTP/|Content-Type|X-VSP-Fallback-Path|Content-Length' /tmp/h | sed 's/\r$//'
  head -c 180 /tmp/b; echo; echo
done

echo "[DONE] If 200 + application/json for reports/run_gate_summary.json => GateStory will show latest RID."
