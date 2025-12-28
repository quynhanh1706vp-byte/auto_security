#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p461b_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need grep; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

echo "[INFO] scan for [VSP_API_HIT] in *.py" | tee -a "$OUT/log.txt"
grep -RIn --include='*.py' '\[VSP_API_HIT\]' . | tee "$OUT/api_hit_grep.txt" || true

python3 - <<'PY'
from pathlib import Path
import re, sys

MARK="VSP_P461B_DETACH_API_HIT_V1"
hit_files=set()

for p in Path(".").rglob("*.py"):
    try:
        s=p.read_text(encoding="utf-8", errors="replace")
    except Exception:
        continue
    if "[VSP_API_HIT]" in s:
        hit_files.add(p)

if not hit_files:
    print("[OK] no python file contains [VSP_API_HIT] (maybe access log / other layer)")
    sys.exit(0)

inject = r'''
# --- VSP_P461B_DETACH_API_HIT_V1 ---
def _vsp_p461b_setup_api_hit_logger():
    import os, logging
    from pathlib import Path
    from logging.handlers import RotatingFileHandler

    root = Path(__file__).resolve().parent
    out = root / "out_ci"
    out.mkdir(parents=True, exist_ok=True)

    api_on = os.getenv("VSP_API_HIT_LOG", "1").lower() not in ("0","false","no","off")
    api_file = os.getenv("VSP_API_HIT_FILE", str(out / "ui_api_hit.log"))

    lg = logging.getLogger("vsp.api_hit")
    lg.propagate = False
    lg.setLevel(logging.INFO)

    if api_on and not lg.handlers:
        h = RotatingFileHandler(api_file, maxBytes=2*1024*1024, backupCount=3, encoding="utf-8")
        h.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        lg.addHandler(h)
    return lg

_VSP_API_HIT_LOGGER = _vsp_p461b_setup_api_hit_logger()

def _vsp_api_hit(msg: str):
    try:
        if not isinstance(msg, str):
            msg = str(msg)
        if msg.startswith("[VSP_API_HIT] "):
            msg = msg[len("[VSP_API_HIT] "):]
        _VSP_API_HIT_LOGGER.info(msg)
    except Exception:
        pass
# --- /VSP_P461B_DETACH_API_HIT_V1 ---
'''

def strip_file_kw(line: str) -> str:
    line = re.sub(r"\s*,\s*file\s*=\s*sys\.(stderr|stdout)\s*\)", ")", line)
    return line

patched=0
for p in sorted(hit_files):
    s=p.read_text(encoding="utf-8", errors="replace")
    if MARK not in s:
        # inject after imports best-effort
        m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", s)
        if m:
            head=m.group(0)
            rest=s[len(head):]
            s=head + inject + "\n" + rest
        else:
            s=inject + "\n" + s

    lines=s.splitlines(True)
    out=[]
    changed=0
    for ln in lines:
        if "[VSP_API_HIT]" in ln:
            lns=ln.lstrip()
            indent=ln[:len(ln)-len(lns)]
            if lns.startswith("print("):
                ln2=indent + lns.replace("print(", "_vsp_api_hit(", 1)
                ln2=strip_file_kw(ln2)
                out.append(ln2); changed+=1; continue
            if re.search(r"\bsys\.(stderr|stdout)\.write\(", lns):
                ln2=re.sub(r"\bsys\.(stderr|stdout)\.write\(", "_vsp_api_hit(", ln)
                out.append(ln2); changed+=1; continue
        out.append(ln)
    s2="".join(out)
    if s2!=s:
        p.write_text(s2, encoding="utf-8")
    print(f"[OK] {p} rewrites={changed}")
    patched += 1

print(f"[DONE] patched_files={patched}")
PY

# syntax check patched files quickly
python3 - <<'PY'
from pathlib import Path
import py_compile, sys
bad=0
for p in Path(".").rglob("*.py"):
    if p.name.endswith(".bak") or ".bak_" in p.name: 
        continue
    try:
        py_compile.compile(str(p), doraise=True)
    except Exception as e:
        print("[BAD]", p, e)
        bad+=1
print("[OK] py_compile bad=", bad)
sys.exit(1 if bad else 0)
PY

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== tail error log ==" | tee -a "$OUT/log.txt"
tail -n 40 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "== tail api_hit log ==" | tee -a "$OUT/log.txt"
tail -n 20 out_ci/ui_api_hit.log 2>/dev/null | tee "$OUT/api_hit_tail.txt" || true

echo "[OK] P461b done" | tee -a "$OUT/log.txt"
