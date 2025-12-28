#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

OUT="out_ci"; TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p58a_fix_js_${TS}"; mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need find; need wc; need sort; need tee

echo "== [P58A] bulk fix JS syntax patterns (TRACE maps + missing commas) ==" | tee "$EVID/summary.txt"

python3 - <<'PY' | tee -a "$EVID/summary.txt"
from pathlib import Path
import re, datetime, shutil

root = Path("static/js")
if not root.exists():
    print("[ERR] static/js missing")
    raise SystemExit(2)

ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
changed = []
scanned = 0

def is_pure_string_line(line: str) -> bool:
    s = line.strip()
    if not s: return False
    if s.startswith("//"): return False
    if s.startswith("/*") or s.endswith("*/"): return False
    # pure: "..." or '...' (optionally trailing comma)
    return bool(re.fullmatch(r"""(['"])(?:\\.|(?!\1).)*\1,?""", s))

def ensure_commas_between_string_literals(lines):
    # if two consecutive array elements are pure string literals but the previous lacks comma -> add comma
    out = lines[:]
    prev_sig_idx = None
    for i in range(len(out)):
        s = out[i].strip()
        if not s or s.startswith("//"):
            continue
        if is_pure_string_line(out[i]):
            if prev_sig_idx is not None and is_pure_string_line(out[prev_sig_idx]):
                prev = out[prev_sig_idx].rstrip("\n")
                if not prev.rstrip().endswith(","):
                    out[prev_sig_idx] = prev + "," + ("\n" if out[prev_sig_idx].endswith("\n") else "")
            prev_sig_idx = i
        else:
            prev_sig_idx = i
    return out

def fix_trace_maps(text: str) -> str:
    t = text

    # 1) object contains severity keys but ends with ", <num> }" => add TRACE:<num>
    def patch_obj(m):
        obj = m.group(0)
        # add key for bare trailing number
        obj2 = re.sub(r",\s*(\d+)\s*}", r", TRACE:\1 }", obj)
        # add key for bare "TRACE"
        obj2 = re.sub(r',\s*"TRACE"\s*}', r', trace:"TRACE" }', obj2)
        obj2 = re.sub(r",\s*'TRACE'\s*}", r", trace:'TRACE' }", obj2)
        # g("TRACE") used bare inside sev label maps
        obj2 = re.sub(r'(\bINFO\s*:\s*g\("INFO"\)\s*,)\s*g\("TRACE"\)', r'\1 TRACE: g("TRACE")', obj2)
        obj2 = re.sub(r"(\bINFO\s*:\s*g\('INFO'\)\s*,)\s*g\('TRACE'\)", r"\1 TRACE: g('TRACE')", obj2)
        return obj2

    # patch only objects that look like severity maps
    t = re.sub(r"\{[^{}]*(CRITICAL|HIGH|MEDIUM|LOW|INFO)[^{}]*\}", patch_obj, t)

    # 2) special map lower->upper had ... , "TRACE"  (no key) => trace:"TRACE"
    t = re.sub(
        r'(\bconst\s+map\s*=\s*\{[^}]*\binfo\s*:\s*"INFO"\s*,)\s*"TRACE"\s*\}',
        r'\1 trace:"TRACE"}',
        t
    )
    return t

def process_file(p: Path):
    global scanned
    scanned += 1
    s = p.read_text(encoding="utf-8", errors="replace")
    orig = s

    # normalize CRLF + BOM
    s = s.replace("\ufeff", "").replace("\r\n", "\n")

    s = fix_trace_maps(s)

    # comma between adjacent string literals (common crash in your failing files)
    lines = s.splitlines(True)
    lines2 = ensure_commas_between_string_literals(lines)
    s = "".join(lines2)

    if s != orig:
        bak = p.with_suffix(p.suffix + f".bak_p58a_{ts}")
        shutil.copy2(p, bak)
        p.write_text(s, encoding="utf-8")
        changed.append(str(p))

for p in sorted(root.rglob("*.js")):
    process_file(p)

print(f"[OK] scanned={scanned} changed={len(changed)}")
if changed:
    for x in changed[:80]:
        print(" -", x)
PY

echo "== [P58A] node --check all static/js/**/*.js ==" | tee -a "$EVID/summary.txt"
fails=0
while IFS= read -r f; do
  if ! node --check "$f" >/dev/null 2>&1; then
    echo "[FAIL] $f" | tee -a "$EVID/fails.txt"
    node --check "$f" 2>&1 | head -n 3 | tee -a "$EVID/fails.txt"
    fails=$((fails+1))
  fi
done < <(find static/js -type f -name '*.js' | sort)

echo "fails=$fails" | tee -a "$EVID/summary.txt"
if [ "$fails" -ne 0 ]; then
  echo "[ERR] still has JS syntax errors. Evidence=$EVID" | tee -a "$EVID/summary.txt"
  exit 2
fi

echo "[PASS] JS syntax clean. Evidence=$EVID" | tee -a "$EVID/summary.txt"
