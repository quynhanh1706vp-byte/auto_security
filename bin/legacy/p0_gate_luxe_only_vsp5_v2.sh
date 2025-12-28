#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need head; need curl; need date

echo "== [1] Patch ALL templates that include vsp_dashboard_luxe_v1.js (gate to /vsp5) =="
python3 - <<'PY'
from pathlib import Path
import re, time

ts=time.strftime("%Y%m%d_%H%M%S")
root=Path("templates")
if not root.exists():
    raise SystemExit("[ERR] missing templates/")

files=[p for p in root.rglob("*.html")]
hits=[]
for p in files:
    s=p.read_text(encoding="utf-8", errors="replace")
    if "vsp_dashboard_luxe_v1.js" in s:
        hits.append(p)

if not hits:
    print("[ERR] no template includes vsp_dashboard_luxe_v1.js")
    raise SystemExit(3)

print("[INFO] templates_with_luxe =", len(hits))
pat = re.compile(r'(<script[^>]+src="[^"]*vsp_dashboard_luxe_v1\.js[^"]*"[^>]*>\s*</script>)', re.I)

for p in hits:
    s=p.read_text(encoding="utf-8", errors="replace")
    # If already gated, skip
    if re.search(r'\{%\s*if\s+request\.path\s*==\s*"/vsp5"\s*%\}.*vsp_dashboard_luxe_v1\.js', s, flags=re.S):
        print("[SKIP] already gated:", p)
        continue

    m=pat.search(s)
    if not m:
        print("[WARN] no direct <script> tag match in:", p)
        continue

    tag=m.group(1)
    gated = '{% if request.path == "/vsp5" %}\n' + tag + '\n{% endif %}'
    s2 = s[:m.start()] + gated + s[m.end():]

    bak=p.with_name(p.name+f".bak_gate_luxe_{ts}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched:", p, "backup:", bak.name)

print("[DONE] template gating complete")
PY

echo
echo "== [2] Restart service (if systemd service name is valid) =="
if [ -n "$SVC" ]; then
  sudo systemctl restart "$SVC" || {
    echo "[ERR] restart failed; showing status/journal"
    sudo systemctl status "$SVC" --no-pager -l | sed -n '1,120p' || true
    sudo journalctl -u "$SVC" -n 120 --no-pager || true
    exit 4
  }
  echo "[OK] restarted $SVC"
else
  echo "[WARN] SVC empty; skip systemctl restart"
fi

echo
echo "== [3] Re-check JS list per tab (luxe must appear ONLY in /vsp5) =="
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "== $p =="
  curl -fsS --max-time 3 --range 0-200000 "$BASE$p" \
    | grep -oE '/static/js/[^"]+\.js\?v=[0-9]+' \
    | head -n 40
done

echo
echo "[DONE] Ctrl+Shift+R in browser."
