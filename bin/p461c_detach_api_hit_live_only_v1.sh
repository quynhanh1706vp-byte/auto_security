#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p461c_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

FILES=(vsp_demo_app.py wsgi_vsp_ui_gateway.py)
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "[ERR] missing $f" | tee -a "$OUT/log.txt"; exit 2; }
  cp -f "$f" "$OUT/${f}.bak_${TS}"
done
echo "[OK] backups in $OUT" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P461C_DETACH_API_HIT_LIVE_ONLY_V1"

inject = r'''
# --- VSP_P461C_DETACH_API_HIT_LIVE_ONLY_V1 ---
def _vsp_p461c_setup_api_hit_logger():
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

_VSP_API_HIT_LOGGER = _vsp_p461c_setup_api_hit_logger()

def _vsp_api_hit(msg: str):
    try:
        if not isinstance(msg, str):
            msg = str(msg)
        if msg.startswith("[VSP_API_HIT] "):
            msg = msg[len("[VSP_API_HIT] "):]
        _VSP_API_HIT_LOGGER.info(msg)
    except Exception:
        pass
# --- /VSP_P461C_DETACH_API_HIT_LIVE_ONLY_V1 ---
'''

def ensure_injected(text: str) -> str:
    if MARK in text:
        return text
    # inject after imports best-effort; else prepend
    m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", text)
    if m:
        head = m.group(0)
        rest = text[len(head):]
        return head + inject + "\n" + rest
    return inject + "\n" + text

def rewrite_api_hit(text: str) -> tuple[str,int]:
    n=0

    # 1) rewrite any print(...[VSP_API_HIT]...) even if preceded by "if ...: "
    #    example: if _vsp_noise_enabled(): print(f"[VSP_API_HIT] {request.method} {fp}", flush=True)
    text2, k = re.subn(
        r'print\(\s*(f?["\']\[VSP_API_HIT\][^)]*)\)\s*(?:,\s*flush\s*=\s*True\s*)?',
        r'_vsp_api_hit(\1)',
        text
    )
    n += k
    text = text2

    # 2) rewrite sys.stderr.write / sys.stdout.write
    text2, k = re.subn(r'\bsys\.(stderr|stdout)\.write\(', '_vsp_api_hit(', text)
    n += k
    text = text2

    # 3) rewrite _e.write(f"[VSP_API_HIT] ...\n")  (common in wsgi)
    text2, k = re.subn(r'\b_e\.write\(\s*(f?["\']\[VSP_API_HIT\][^)]*)\)', r'_vsp_api_hit(\1)', text)
    n += k
    text = text2

    return text, n

for fname in ["vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]:
    p = Path(fname)
    s = p.read_text(encoding="utf-8", errors="replace")
    s = ensure_injected(s)
    s2, n = rewrite_api_hit(s)
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] {fname}: rewrites={n}")
PY

# compile ONLY the live runtime files (avoid repo rác)
python3 -m py_compile vsp_demo_app.py wsgi_vsp_ui_gateway.py | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== tail error log ==" | tee -a "$OUT/log.txt"
tail -n 25 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "== tail api_hit log ==" | tee -a "$OUT/log.txt"
tail -n 25 out_ci/ui_api_hit.log 2>/dev/null | tee "$OUT/api_hit_tail.txt" || true

echo "[OK] P461c done" | tee -a "$OUT/log.txt"
