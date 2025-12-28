#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/p464e_${TS}"
mkdir -p "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1" | tee -a "$OUT/log.txt"; exit 2; }; }
need python3; need date; need grep; need head
command -v sudo >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP" | tee -a "$OUT/log.txt"; exit 2; }

cp -f "$APP" "$OUT/${APP}.bak_${TS}"
echo "[OK] backup => $OUT/${APP}.bak_${TS}" | tee -a "$OUT/log.txt"

python3 - <<'PY'
from pathlib import Path
import re, sys

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P464E_PING_ENDPOINT_V1"
if MARK in s:
    print("[OK] already has ping endpoint")
    sys.exit(0)

# insert near other /api/vsp routes: after first occurrence of "/api/vsp/"
m=re.search(r"@app\.route\(\s*['\"]\/api\/vsp\/", s)
if not m:
    # fallback: append near end
    ins = "\n\n"
else:
    ins = s[:m.start()]
    s = s[m.start():]

endpoint = r'''
# --- VSP_P464E_PING_ENDPOINT_V1 ---
@app.route("/api/vsp/p464_ping", methods=["GET"])
def vsp_p464_ping():
    try:
        return jsonify({"ok": 1, "ts": int(time.time())})
    except Exception:
        return ("", 204)
# --- /VSP_P464E_PING_ENDPOINT_V1 ---
'''.strip("\n") + "\n\n"

if m:
    s2 = ins + endpoint + s
else:
    s2 = s + endpoint

p.write_text(s2, encoding="utf-8")
print("[OK] injected ping endpoint")
PY

python3 -m py_compile "$APP" | tee -a "$OUT/log.txt"

if command -v systemctl >/dev/null 2>&1; then
  echo "[INFO] restart $SVC" | tee -a "$OUT/log.txt"
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" | tee -a "$OUT/log.txt" || true
fi

echo "[OK] test ping:" | tee -a "$OUT/log.txt"
curl -fsS http://127.0.0.1:8910/api/vsp/p464_ping | head -c 120 | tee -a "$OUT/log.txt"
echo "" | tee -a "$OUT/log.txt"
