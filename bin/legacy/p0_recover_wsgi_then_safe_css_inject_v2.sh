#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
CSS="static/css/vsp_dashboard_polish_v1.css"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_before_recover_${TS}"
echo "[BACKUP] ${WSGI}.bak_before_recover_${TS}"

echo "== [0] if wsgi broken -> restore latest compiling backup =="
if python3 -m py_compile "$WSGI" >/dev/null 2>&1; then
  echo "[OK] current wsgi already compiles"
else
  echo "[WARN] current wsgi broken -> searching backups..."
  GOOD="$(python3 - <<'PY'
from pathlib import Path
import subprocess, sys

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for b in baks:
    try:
        subprocess.check_call([sys.executable, "-m", "py_compile", str(b)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print(str(b))
        raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(1)
PY
)" || true

  if [ -z "${GOOD:-}" ]; then
    echo "[ERR] cannot find compiling backup for $WSGI"
    exit 3
  fi

  cp -f "$GOOD" "$WSGI"
  echo "[OK] restored from: $GOOD"
fi

echo "== [1] ensure polish css file exists (safe) =="
mkdir -p "$(dirname "$CSS")"
if [ ! -s "$CSS" ]; then
  cat > "$CSS" <<'CSS'
/* VSP_DASHBOARD_POLISH_V1 (force-visible) */
:root{
  --bg0:#070e1a; --bg1:#0b1220;
  --line:rgba(255,255,255,.10);
  --txt:rgba(226,232,240,.92);
  --muted:rgba(148,163,184,.85);
  --accent:rgba(56,189,248,.88);
  --accent2:rgba(168,85,247,.66);
  --r:16px;
}
html,body{ background:linear-gradient(180deg,var(--bg0),var(--bg1)); color:var(--txt); }
#vsp5_root{ padding:14px 16px; max-width:1480px; margin:0 auto; }
a{ color:var(--txt); } a:hover{ color:rgba(255,255,255,.98); }
CSS
  echo "[OK] wrote $CSS"
else
  echo "[OK] css exists: $CSS"
fi

echo "== [2] patch WSGI to inject CSS link safely (single quotes) =="
cp -f "$WSGI" "${WSGI}.bak_safeinject_${TS}"
echo "[BACKUP] ${WSGI}.bak_safeinject_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_SAFE_POLISH_CSS_INJECT_V2"
if MARK not in s:
    s = "\n# ===================== " + MARK + " =====================\n" + s

# If already present, do nothing
if "vsp_dashboard_polish_v1.css" in s:
    w.write_text(s, encoding="utf-8")
    print("[OK] polish css already referenced in source")
else:
    # Replace inside any python string content that contains the literal <title>VSP5</title>
    # IMPORTANT: use only single quotes in HTML attributes to avoid breaking python "..."
    # Use \\n so runtime HTML has new line.
    repl = "<title>VSP5</title>\\\\n  <link rel='stylesheet' href='/static/css/vsp_dashboard_polish_v1.css'/>"
    n0 = s.count("<title>VSP5</title>")
    if n0 == 0:
        print("[WARN] cannot find <title>VSP5</title> in source; leaving unchanged")
        w.write_text(s, encoding="utf-8")
    else:
        s2 = s.replace("<title>VSP5</title>", repl, 1)
        w.write_text(s2, encoding="utf-8")
        print("[OK] injected polish css after <title>VSP5</title> (safe)")

PY

echo "== [3] compile check =="
python3 -m py_compile "$WSGI"

echo "== [4] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.8

echo "== [5] verify /vsp5 includes polish css =="
HTML="$(curl -fsS "$BASE/vsp5" || true)"
echo "$HTML" | grep -n "vsp_dashboard_polish_v1.css" || echo "[WARN] /vsp5 HTML not showing polish css yet"

echo "[DONE] Hard refresh /vsp5 (Ctrl+Shift+R)"
