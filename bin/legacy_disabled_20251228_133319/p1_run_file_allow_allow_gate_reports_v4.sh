#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"

echo "== find python file that builds allowlist for run_file_allow (STRICT *.py only) =="

TARGET="$(python3 - <<'PY'
from pathlib import Path

root = Path(".")
cands = []
for p in root.rglob("*.py"):
    if "out_ci" in p.parts or "bin" in p.parts:
        continue
    try:
        s = p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    # strong signals: allowlist json + findings_unified html path (the one seen in 403 response)
    if ("reports/findings_unified.html" in s) and ("allow" in s) and ("run_file" in s):
        cands.append(str(p))

# fallback: still likely place
if not cands:
    for p in root.rglob("*.py"):
        if "out_ci" in p.parts or "bin" in p.parts:
            continue
        try:
            s = p.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue
        if "VSP_RUN_FILE_ALLOW" in s or "/api/vsp/run_file_allow" in s or "run_file_allow" in s:
            cands.append(str(p))
            break

print(cands[0] if cands else "")
PY
)"

[ -n "$TARGET" ] || { echo "[ERR] cannot locate backend *.py for run_file_allow allowlist"; exit 2; }
case "$TARGET" in
  *.py) ;;
  *) echo "[ERR] TARGET is not .py => '$TARGET'"; exit 2;;
esac

echo "[INFO] TARGET=$TARGET"
cp -f "$TARGET" "${TARGET}.bak_allow_gate_reports_v4_${TS}"
echo "[BACKUP] ${TARGET}.bak_allow_gate_reports_v4_${TS}"

python3 - "$TARGET" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P1_ALLOW_GATE_REPORTS_V4"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

want = [
  "run_gate_summary.json",
  "run_gate.json",
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]

def inject_after(anchor: str, text: str) -> tuple[str,bool]:
    if anchor not in text:
        return text, False
    # insert missing entries right after the first quoted anchor occurrence
    m = re.search(r'([\'"])' + re.escape(anchor) + r'\1', text)
    if not m:
        return text, False
    q = m.group(1)
    ins = ""
    for w in want:
        if re.search(r'([\'"])' + re.escape(w) + r'\1', text) is None:
            ins += f", {q}{w}{q}"
    if not ins:
        return text, True
    return text[:m.end()] + ins + text[m.end():], True

s2, ok = inject_after("reports/findings_unified.html", s)
if not ok:
    s2, ok = inject_after("reports/findings_unified.csv", s)
if not ok:
    # last resort: try to inject into the JSON allow response itself: {"allow":[...]}
    m = re.search(r'("allow"\s*:\s*\[)', s)
    if m:
        # inject at list head if not present
        add = ""
        for w in want:
            if w not in s:
                add += f'"{w}", '
        if add:
            s2 = s[:m.end()] + add + s[m.end():]
            ok = True

if not ok:
    s2 = s + f"\n\n# {marker} (FAILED to locate allowlist literal)\n"
    print("[WARN] could not locate allowlist; appended marker only.")
else:
    s2 = s2 + f"\n\n# {marker}\n"
    print("[OK] injected gate paths into allowlist")

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$TARGET"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.8

echo "== verify (expect NOT 403 anymore for reports/run_gate*) =="
RID="RUN_khach6_FULL_20251129_133030"
for path in "reports/run_gate_summary.json" "reports/run_gate.json"; do
  echo "-- $path"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$path" || echo "[curl rc=$?]"
  sed -n '1,10p' /tmp/h | sed 's/\r$//'
  head -c 160 /tmp/b; echo; echo
done

echo "[DONE] HARD refresh /vsp5 (Ctrl+Shift+R)."
