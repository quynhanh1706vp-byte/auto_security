#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p461d_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$W" "$OUT/${W}.bak_${TS}"
echo "[OK] backup => $OUT/${W}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P461D_STDERR_FILTER_API_HIT_V1"
if MARK in s:
    print("[OK] already patched P461d")
    sys.exit(0)

block = r'''
# --- VSP_P461D_STDERR_FILTER_API_HIT_V1 ---
def _vsp_p461d_setup_api_hit_logger():
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

_VSP_API_HIT_LOGGER = _vsp_p461d_setup_api_hit_logger()

def _vsp_api_hit(msg):
    try:
        if msg is None:
            return
        if not isinstance(msg, str):
            msg = str(msg)
        msg = msg.rstrip("\n")
        if msg.startswith("[VSP_API_HIT] "):
            msg = msg[len("[VSP_API_HIT] "):]
        _VSP_API_HIT_LOGGER.info(msg)
    except Exception:
        pass

def _vsp_p461d_install_stderr_filter():
    import sys as _sys
    _orig = _sys.stderr

    class _VspStderrFilter:
        def __init__(self, orig):
            self._orig = orig
        def write(self, data):
            try:
                # bytes: pass through
                if isinstance(data, (bytes, bytearray)):
                    return self._orig.buffer.write(data) if hasattr(self._orig, "buffer") else self._orig.write(data)
                if isinstance(data, str) and data.startswith("[VSP_API_HIT]"):
                    _vsp_api_hit(data)
                    return len(data)
            except Exception:
                pass
            return self._orig.write(data)
        def flush(self):
            try:
                return self._orig.flush()
            except Exception:
                return None
        def __getattr__(self, name):
            return getattr(self._orig, name)

    # replace stderr as early as possible; non-hit logs keep same behavior
    _sys.stderr = _VspStderrFilter(_orig)

_vsp_p461d_install_stderr_filter()
# --- /VSP_P461D_STDERR_FILTER_API_HIT_V1 ---
'''

# Insert after the first import block (best-effort)
m = re.search(r"(?s)\A((?:\s*#.*\n)*)((?:\s*(?:from|import)\s+.*\n)+)", s)
if m:
    head=m.group(0)
    rest=s[len(head):]
    s2=head + block + "\n" + rest
else:
    s2=block + "\n" + s

p.write_text(s2, encoding="utf-8")
print("[OK] injected P461d into", p)
PY

python3 -m py_compile "$W" | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "== tail error log ==" | tee -a "$OUT/log.txt"
tail -n 25 out_ci/ui_8910.error.log 2>/dev/null | tee "$OUT/error_tail.txt" || true

echo "== tail api_hit log ==" | tee -a "$OUT/log.txt"
tail -n 25 out_ci/ui_api_hit.log 2>/dev/null | tee "$OUT/api_hit_tail.txt" || true

echo "[OK] P461d done" | tee -a "$OUT/log.txt"
