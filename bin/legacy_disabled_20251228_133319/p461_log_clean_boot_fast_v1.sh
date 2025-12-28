#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p461_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need sed
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P461_LOG_CLEAN_BOOT_FAST_V1"
if MARK in s:
    print("[OK] already patched P461")
    sys.exit(0)

# 1) inject logger helper (idempotent marker)
inject = r'''
# --- VSP_P461_LOG_CLEAN_BOOT_FAST_V1 ---
def _vsp_p461_setup_loggers():
    """
    P461: keep behavior, clean logs.
    - Move noisy "[VSP_API_HIT]" to rotating file out_ci/ui_api_hit.log
    - Quiet werkzeug by default (can re-enable via env)
    Env:
      VSP_API_HIT_LOG=1|0
      VSP_API_HIT_FILE=/path/to/file
      VSP_WERKZEUG_QUIET=1|0
    """
    import os, logging
    from pathlib import Path
    from logging.handlers import RotatingFileHandler

    root = Path(__file__).resolve().parent
    out = root / "out_ci"
    out.mkdir(parents=True, exist_ok=True)

    api_on = os.getenv("VSP_API_HIT_LOG", "1").lower() not in ("0","false","no","off")
    api_file = os.getenv("VSP_API_HIT_FILE", str(out / "ui_api_hit.log"))

    api_logger = logging.getLogger("vsp.api_hit")
    api_logger.propagate = False
    api_logger.setLevel(logging.INFO)

    if api_on and not api_logger.handlers:
        h = RotatingFileHandler(api_file, maxBytes=2*1024*1024, backupCount=3, encoding="utf-8")
        h.setFormatter(logging.Formatter("%(asctime)s %(message)s"))
        api_logger.addHandler(h)

    wz_quiet = os.getenv("VSP_WERKZEUG_QUIET", "1").lower() not in ("0","false","no","off")
    if wz_quiet:
        logging.getLogger("werkzeug").setLevel(logging.ERROR)

    return api_logger

_VSP_API_HIT_LOGGER = _vsp_p461_setup_loggers()

def _vsp_api_hit(msg: str):
    try:
        if not isinstance(msg, str):
            msg = str(msg)
        if msg.startswith("[VSP_API_HIT] "):
            msg = msg[len("[VSP_API_HIT] "):]
        _VSP_API_HIT_LOGGER.info(msg)
    except Exception:
        pass
# --- /VSP_P461_LOG_CLEAN_BOOT_FAST_V1 ---
'''

# place after imports block (best-effort)
if "import " in s:
    # find end of top import section
    m = re.search(r"(?s)\A(.*?\n)(\s*(?:import|from)\s+.*?\n(?:\s*(?:import|from)\s+.*?\n)*)", s)
    if m:
        head = m.group(0)
        rest = s[len(head):]
        s = head + inject + "\n" + rest
    else:
        s = inject + "\n" + s
else:
    s = inject + "\n" + s

# 2) rewrite noisy API HIT prints into _vsp_api_hit(...)
lines = s.splitlines(True)
out_lines = []
changed = 0

def strip_file_kw(line: str) -> str:
    # remove ", file=sys.stderr" or ", file=sys.stdout"
    line = re.sub(r"\s*,\s*file\s*=\s*sys\.(stderr|stdout)\s*\)", ")", line)
    return line

for ln in lines:
    if "[VSP_API_HIT]" in ln:
        lns = ln.lstrip()
        indent = ln[:len(ln)-len(lns)]
        if lns.startswith("print("):
            ln2 = indent + lns.replace("print(", "_vsp_api_hit(", 1)
            ln2 = strip_file_kw(ln2)
            out_lines.append(ln2)
            changed += 1
            continue
        # sys.stderr.write("...") / sys.stdout.write("...")
        if re.search(r"\bsys\.(stderr|stdout)\.write\(", lns):
            # convert sys.stderr.write(X) -> _vsp_api_hit(X)
            ln2 = re.sub(r"\bsys\.(stderr|stdout)\.write\(", "_vsp_api_hit(", ln)
            out_lines.append(ln2)
            changed += 1
            continue
    out_lines.append(ln)

s2 = "".join(out_lines)

p.write_text(s2, encoding="utf-8")
print(f"[OK] patched P461 (api_hit_rewrites={changed})")
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restarting $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[INFO] quick check: error log tail" | tee -a "$OUT/log.txt"
tail -n 40 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "[OK] P461 done. API hit log (if enabled): out_ci/ui_api_hit.log" | tee -a "$OUT/log.txt"
