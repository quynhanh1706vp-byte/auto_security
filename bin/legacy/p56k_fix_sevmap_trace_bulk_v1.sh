#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p56k_fix_sev_${TS}"; mkdir -p "$EVID"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need ls; need head; need wc

latest_p56g="$(ls -1dt out_ci/p56g_js_syntax_* 2>/dev/null | head -n 1 || true)"
if [ -z "${latest_p56g:-}" ] || [ ! -d "$latest_p56g" ]; then
  echo "[ERR] cannot find latest out_ci/p56g_js_syntax_*; run P56G first." | tee "$EVID/summary.txt"
  exit 2
fi

fails="$latest_p56g/fails.txt"
if [ ! -s "$fails" ]; then
  echo "[OK] no fails in $fails" | tee "$EVID/summary.txt"
  exit 0
fi

cp -f "$fails" "$EVID/fails_in.txt"
echo "== [P56K] fix sev map stray ', 0 }' => ', TRACE:0 }' ==" | tee "$EVID/summary.txt"
echo "[OK] source_fails=$(wc -l < "$EVID/fails_in.txt") from $latest_p56g" | tee -a "$EVID/summary.txt"

python3 - <<'PY'
from pathlib import Path
import re, shutil, datetime

evid = Path("out_ci").resolve()
latest = sorted(evid.glob("p56k_fix_sev_*"))[-1]
fails_in = (latest/"fails_in.txt").read_text().splitlines()

patched=[]
still_fail=[]

pat1 = re.compile(r'(\bINFO\s*:\s*0\s*,)\s*0(\s*[\}\]])')   # INFO:0, 0}
pat2 = re.compile(r'(,\s*)0(\s*[\}\]])')                   # , 0}

for rel in fails_in:
    f = Path(rel.strip())
    if not f.exists() or f.suffix != ".js":
        continue
    s = f.read_text(encoding="utf-8", errors="replace")
    orig = s

    # safe targeted replacements
    s, n1 = pat1.subn(r'\1 TRACE:0\2', s)
    # only apply pat2 if it looks like severity map block (reduce risk)
    if "CRITICAL" in s and "HIGH" in s and "MEDIUM" in s and "LOW" in s and "INFO" in s:
        s, n2 = pat2.subn(r'\1TRACE:0\2', s, count=1)
    else:
        n2 = 0

    if s != orig:
        ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        bak = f.with_suffix(f".js.bak_p56k_{ts}")
        shutil.copy2(f, bak)
        f.write_text(s, encoding="utf-8")
        patched.append((str(f), str(bak), n1, n2))

# write report
(latest/"patched.txt").write_text("\n".join([p[0] for p in patched])+"\n", encoding="utf-8")
print("[OK] patched_files=", len(patched))
for p in patched[:50]:
    print("[PATCHED]", p)
PY | tee -a "$EVID/summary.txt"

# re-check only patched files
fails2=0
> "$EVID/after_fails.txt"
if [ -s "$EVID/patched.txt" ]; then
  while read -r f; do
    [ -n "$f" ] || continue
    if node --check "$f" >/dev/null 2>"$EVID/$(basename "$f").after.err"; then
      echo "[OK] after syntax: $f" | tee -a "$EVID/summary.txt"
    else
      echo "[FAIL] after syntax: $f" | tee -a "$EVID/summary.txt"
      echo "$f" >> "$EVID/after_fails.txt"
      fails2=$((fails2+1))
    fi
  done < "$EVID/patched.txt"
fi

echo "[DONE] Evidence=$EVID after_fails=${fails2}" | tee -a "$EVID/summary.txt"
[ "$fails2" -eq 0 ] && exit 0 || exit 1
