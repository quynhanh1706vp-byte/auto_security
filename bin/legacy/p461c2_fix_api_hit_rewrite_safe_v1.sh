#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p461c2_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need ls; need head; need grep
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

# 1) find the latest P461c backup and restore (this fixes current broken syntax)
last_p461c="$(ls -1dt out_ci/p461c_* 2>/dev/null | head -n1 || true)"
[ -n "$last_p461c" ] || { echo "[ERR] no out_ci/p461c_* backup dir found" | tee -a "$OUT/log.txt"; exit 2; }

for f in vsp_demo_app.py wsgi_vsp_ui_gateway.py; do
  bak="$(ls -1 "$last_p461c/${f}.bak_"* 2>/dev/null | head -n1 || true)"
  [ -n "$bak" ] || { echo "[ERR] missing backup for $f in $last_p461c" | tee -a "$OUT/log.txt"; exit 2; }
  cp -f "$bak" "$f"
  echo "[OK] restored $f <= $bak" | tee -a "$OUT/log.txt"
done

# 2) apply SAFE rewrite (line-based; never spans lines; removes flush=True correctly)
python3 - <<'PY'
from pathlib import Path
import re, sys

MARK="VSP_P461C2_DETACH_API_HIT_SAFE_V1"

inject = r'''
# --- VSP_P461C2_DETACH_API_HIT_SAFE_V1 ---
def _vsp_p461c2_setup_api_hit_logger():
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

_VSP_API_HIT_LOGGER = _vsp_p461c2_setup_api_hit_logger()

def _vsp_api_hit(msg):
    try:
        if not isinstance(msg, str):
            msg = str(msg)
        if msg.startswith("[VSP_API_HIT] "):
            msg = msg[len("[VSP_API_HIT] "):]
        _VSP_API_HIT_LOGGER.info(msg)
    except Exception:
        pass
# --- /VSP_P461C2_DETACH_API_HIT_SAFE_V1 ---
'''

def inject_once(text: str) -> str:
    if MARK in text:
        return text
    # put after initial imports if possible
    m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", text)
    if m:
        head = m.group(0)
        rest = text[len(head):]
        return head + inject + "\n" + rest
    return inject + "\n" + text

# Remove flush=True inside a function call argument list (simple, line-safe)
def drop_flush_true_in_line(line: str) -> str:
    # handles: , flush=True   or   flush=True,   or   (flush=True)
    line = re.sub(r",\s*flush\s*=\s*True\s*(?=[,)])", "", line)
    line = re.sub(r"\(\s*flush\s*=\s*True\s*\)", "()", line)
    line = re.sub(r"flush\s*=\s*True\s*,\s*", "", line)
    return line

def rewrite_line(line: str):
    changed = 0
    if "[VSP_API_HIT]" not in line:
        return line, changed

    # 1) sys.stderr.write / sys.stdout.write / _e.write -> _vsp_api_hit
    if "sys.stderr.write(" in line or "sys.stdout.write(" in line or "_e.write(" in line:
        line2 = line
        line2 = line2.replace("sys.stderr.write(", "_vsp_api_hit(")
        line2 = line2.replace("sys.stdout.write(", "_vsp_api_hit(")
        line2 = line2.replace("_e.write(", "_vsp_api_hit(")
        if line2 != line:
            line = line2
            changed += 1

    # 2) print(...) -> _vsp_api_hit(...)  (only when print( is on SAME LINE)
    #    handle inline: if cond: print(...)
    if "print(" in line:
        line2 = line.replace("print(", "_vsp_api_hit(", 1)
        if line2 != line:
            line = line2
            changed += 1

    # 3) remove flush=True (if present)
    line2 = drop_flush_true_in_line(line)
    if line2 != line:
        line = line2
        changed += 1

    return line, changed

for fname in ["vsp_demo_app.py", "wsgi_vsp_ui_gateway.py"]:
    p = Path(fname)
    s = p.read_text(encoding="utf-8", errors="replace")
    s = inject_once(s)

    out_lines = []
    rewrites = 0
    for ln in s.splitlines(True):
        ln2, c = rewrite_line(ln)
        out_lines.append(ln2)
        rewrites += c

    s2 = "".join(out_lines)
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] {fname}: line_rewrites={rewrites}")
PY

# 3) compile ONLY runtime files
python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py | tee -a "$OUT/log.txt"

# 4) restart + show tails
if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== tail error log ==" | tee -a "$OUT/log.txt"
tail -n 30 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "== tail api_hit log ==" | tee -a "$OUT/log.txt"
tail -n 30 out_ci/ui_api_hit.log 2>/dev/null | tee "$OUT/api_hit_tail.txt" || true

echo "[OK] P461c2 done" | tee -a "$OUT/log.txt"
