#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need sed; need curl

TS="$(date +%Y%m%d_%H%M%S)"

echo "== locate REAL allowlist source (look for reports/findings_unified.html) =="
TARGET="$(grep -RIl --exclude='*.bak_*' --exclude-dir='out_ci' --exclude-dir='bin' --include='*.py' \
  "reports/findings_unified.html" . 2>/dev/null | head -n1 || true)"

# fallback: look for the allow JSON key pattern
if [ -z "$TARGET" ]; then
  TARGET="$(grep -RIl --exclude='*.bak_*' --exclude-dir='out_ci' --exclude-dir='bin' --include='*.py' \
    "\"allow\"" . 2>/dev/null | head -n1 || true)"
fi

[ -n "$TARGET" ] || { echo "[ERR] cannot locate backend allowlist python source"; exit 2; }
[ -f "$TARGET" ] || { echo "[ERR] missing $TARGET"; exit 2; }

cp -f "$TARGET" "${TARGET}.bak_allow_gate_reports_${TS}"
echo "[BACKUP] ${TARGET}.bak_allow_gate_reports_${TS}"
echo "[INFO] patch target: $TARGET"

python3 - "$TARGET" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P1_ALLOW_GATE_REPORTS_V3"
if marker in s:
    print("[OK] already patched:", p)
    raise SystemExit(0)

want = [
  "run_gate_summary.json",
  "run_gate.json",
  "reports/run_gate_summary.json",
  "reports/run_gate.json",
]

def ensure_entries_in_literal(text: str) -> tuple[str,int]:
    """
    Heuristic: inject new entries near existing allowlist literals.
    We try:
      - insert after reports/findings_unified.html
      - else insert after reports/findings_unified.csv
      - else no-op
    """
    n=0
    def inject_after(anchor: str, t: str) -> tuple[str,int]:
        nonlocal n
        if anchor not in t:
            return t, 0
        # Find the first occurrence of the anchor inside quotes and inject after it
        # Keep quote style consistent (single/double) if possible.
        pat = re.compile(r'([\'"])' + re.escape(anchor) + r'\1')
        m = pat.search(t)
        if not m:
            return t, 0
        q = m.group(1)
        ins = ""
        for w in want:
            if w not in t:
                ins += f", {q}{w}{q}"
        if not ins:
            return t, 0
        # inject right after the matched quoted anchor
        t2 = t[:m.end()] + ins + t[m.end():]
        n += 1
        return t2, 1

    t = text
    t, ok = inject_after("reports/findings_unified.html", t)
    if ok: return t, n
    t, ok = inject_after("reports/findings_unified.csv", t)
    if ok: return t, n
    return t, n

s2, n = ensure_entries_in_literal(s)

# If nothing changed, append a small helper allowlist set and try to merge if a name exists
# (Still safe: no behavior change unless developer uses it later.)
if s2 == s:
    # As last resort, just append a comment marker so we know the attempt ran.
    s2 = s + "\n\n# " + marker + " (no literal patched; please patch allowlist manually)\n"
    print("[WARN] could not find allowlist literal to inject into; appended marker only.")
else:
    # add marker near end
    s2 = s2 + "\n\n# " + marker + "\n"
    print(f"[OK] injected allow gate paths into allowlist literal (edits={n})")

p.write_text(s2, encoding="utf-8")
PY

echo "== py_compile =="
python3 -m py_compile "$TARGET"

echo "== restart 8910 =="
sudo systemctl restart vsp-ui-8910.service || true
sleep 0.8

echo "== verify (expect NOT 403). Using known RID from your log =="
RID="RUN_khach6_FULL_20251129_133030"
for path in "reports/run_gate_summary.json" "reports/run_gate.json" "run_gate_summary.json" "run_gate.json"; do
  echo "-- $path"
  curl -sS -D /tmp/h -o /tmp/b -w "[HTTP]=%{http_code} [SIZE]=%{size_download}\n" \
    "$BASE/api/vsp/run_file_allow?rid=$RID&path=$path" || echo "[curl rc=$?]"
  sed -n '1,8p' /tmp/h | sed 's/\r$//'
  head -c 120 /tmp/b; echo; echo
done

echo "[DONE] Now HARD refresh /vsp5 (Ctrl+Shift+R)."
