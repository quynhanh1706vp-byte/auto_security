#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
TPL="templates/vsp_dashboard_2025.html"
PIDF="out_ci/ui_8910.pid"
ERR="out_ci/ui_8910.error.log"
ACC="out_ci/ui_8910.access.log"
SNAPDIR="out_ci/snapshots"
mkdir -p out_ci "$SNAPDIR" static

# (0) stop 8910 clean (avoid "Address already in use")
PID="$(cat "$PIDF" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.8

# (1) patch template: hard-disable tools_status script (it is syntactically broken + can null-deref)
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }
cp -f "$TPL" "$TPL.bak_freeze_${TS}" && echo "[BACKUP] $TPL.bak_freeze_${TS}"

python3 - <<'PY'
import re
from pathlib import Path
p = Path("templates/vsp_dashboard_2025.html")
s = p.read_text(encoding="utf-8", errors="ignore")

# remove script tags that load tools status (any variant)
before = s
s = re.sub(r'(?is)\s*<script[^>]+src="[^"]*vsp_tools_status[^"]*"[^>]*>\s*</script>\s*', "\n<!-- disabled: vsp_tools_status (freeze_safe) -->\n", s)
s = re.sub(r'(?is)\s*<script[^>]+src="[^"]*tools_status[^"]*"[^>]*>\s*</script>\s*', "\n<!-- disabled: tools_status (freeze_safe) -->\n", s)

if s == before:
    print("[WARN] template had no tools_status script tag to remove")
else:
    print("[OK] removed tools_status script tags from template")

p.write_text(s, encoding="utf-8")
PY

# (2) add a favicon to kill 404 noise (not critical but cleaner)
if [ ! -f static/favicon.ico ]; then
  : > static/favicon.ico
  echo "[OK] created static/favicon.ico"
fi

# (3) create a restorable snapshot of UI assets (template + static)
LIST="$SNAPDIR/ui_snapshot_list_${TS}.txt"
python3 - <<'PY'
from pathlib import Path
paths = [
  Path("templates/vsp_dashboard_2025.html"),
  Path("static/js"),
  Path("static/css"),
  Path("static/vendor"),
  Path("static/favicon.ico"),
]
existing = []
for x in paths:
  if x.exists():
    existing.append(str(x))
Path("out_ci/snapshots/ui_snapshot_list_"+__import__("datetime").datetime.now().strftime("%Y%m%d_%H%M%S")+".txt").write_text("\n".join(existing)+"\n", encoding="utf-8")
print("[OK] snapshot paths:", existing)
PY

# find the newest list file we just wrote
LIST="$(ls -1t $SNAPDIR/ui_snapshot_list_*.txt | head -n1)"
SNAP="$SNAPDIR/ui_safe_${TS}.tgz"
tar -czf "$SNAP" -T "$LIST"
ln -sf "$(basename "$SNAP")" "$SNAPDIR/ui_safe_latest.tgz"
echo "[OK] snapshot => $SNAP (also ui_safe_latest.tgz)"

# (4) write restore script (1-liner restore)
cat > /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_restore_ui_snapshot_latest_v1.sh <<'RSH'
#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
SNAP="out_ci/snapshots/ui_safe_latest.tgz"
[ -f "$SNAP" ] || { echo "[ERR] missing $SNAP"; exit 2; }
tar -xzf "$SNAP" -C /home/test/Data/SECURITY_BUNDLE/ui --overwrite
echo "[OK] restored snapshot: $SNAP"
RSH
chmod +x /home/test/Data/SECURITY_BUNDLE/ui/bin/vsp_restore_ui_snapshot_latest_v1.sh

# (5) start UI
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PIDF" \
  --access-logfile "$ACC" --error-logfile "$ERR" \
  > /dev/null 2>&1 &

sleep 0.8
echo "== check =="
ss -ltnp | grep ':8910' || true
curl -sS -m 2 http://127.0.0.1:8910/vsp4 | head -n 5 || true
echo "[DONE] Freeze+Snapshot+Restart OK. Hard refresh: Ctrl+Shift+R"
