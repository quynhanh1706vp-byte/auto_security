#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need ls; need head; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="vsp-ui-8910.service"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
cp -f "$W" "${W}.bak_runfileallow_v9_${TS}"
echo "[BACKUP] ${W}.bak_runfileallow_v9_${TS}"

python3 - <<'PY'
from __future__ import annotations
from pathlib import Path
import re, py_compile, sys

W = Path("wsgi_vsp_ui_gateway.py")

def compiles(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

# 0) auto-restore if current is broken
if not compiles(W):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    restored = None
    for b in baks[:200]:
        if compiles(b):
            W.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            restored = b.name
            break
    if not restored:
        print("[FATAL] current wsgi does not compile and no compiling backup found")
        sys.exit(2)
    print(f"[OK] restored from compiling backup: {restored}")
else:
    print("[OK] current wsgi compiles")

s = W.read_text(encoding="utf-8", errors="replace")
lines = s.splitlines(True)

# Helper: insert a list item after a matching *list-item line* (not dict key)
# Matches:   "run_gate_summary.json",
item_pat = re.compile(r'^(?P<ind>\s*)(?P<q>["\'])'
                      r'(?P<name>run_gate_summary\.json|run_gate\.json)'
                      r'(?P=q)\s*,\s*$')

def already_has_reports_variant(window: list[str], base: str) -> bool:
    target = f"reports/{base}"
    return any(target in x for x in window)

inserted = 0
i = 0
while i < len(lines):
    m = item_pat.match(lines[i])
    if m and (":" not in lines[i]):  # extra guard: dict keys have ':'
        base = m.group("name")
        # look ahead a bit to avoid double insert inside same list
        win = lines[max(0, i-30):min(len(lines), i+60)]
        if not already_has_reports_variant(win, base):
            ind = m.group("ind"); q = m.group("q")
            ins = f'{ind}{q}reports/{base}{q},\n'
            lines.insert(i+1, ins)
            inserted += 1
            i += 1
    i += 1

# Also handle single-line lists: [...,"run_gate_summary.json",...]
# Only if reports variant not present anywhere near the token.
if inserted == 0:
    s2 = s
    for base in ["run_gate_summary.json", "run_gate.json"]:
        if f"reports/{base}" not in s2 and base in s2:
            # insert right after first occurrence of "base",
            s2, n = re.subn(rf'("{re.escape(base)}"\s*,)',
                           rf'\1 "reports/{base}",',
                           s2, count=1)
            if n:
                inserted += n
    if inserted:
        lines = s2.splitlines(True)

W.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted reports gate variants: {inserted}")

# compile gate
py_compile.compile(str(W), doraise=True)
print("[OK] py_compile OK")

# sanity: ensure allow list text now contains reports/run_gate_summary.json somewhere
s3 = W.read_text(encoding="utf-8", errors="replace")
if "reports/run_gate_summary.json" not in s3:
    print("[WARN] file still does not contain reports/run_gate_summary.json (unexpected)")
PY

echo "== restart =="
systemctl restart "$SVC" || true
sleep 0.8

echo "== wait /api/vsp/runs =="
for i in {1..30}; do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" >/dev/null 2>&1; then echo "[OK] up"; break; fi
  sleep 0.3
done

echo "== sanity: run_file_allow should NOT 403-not-allowed for reports/run_gate_summary.json =="
RID="$(curl -fsS "$BASE/api/vsp/runs?limit=1" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["items"][0]["run_id"])' 2>/dev/null || true)"
echo "[RID]=${RID:-<empty>}"

if [ -n "${RID:-}" ]; then
  curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/run_gate_summary.json" | head -n 60
else
  echo "[ERR] cannot resolve RID (runs API not returning JSON?)"
fi

echo "[DONE] Hard reload /runs (Ctrl+Shift+R). Check console: 403 spam should stop."
