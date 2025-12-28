#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_p3k26_v25_${TS}"
echo "[BACKUP] ${W}.bak_p3k26_v25_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_CACHEHOT_LAZY_V25"
if TAG in s:
    print("[OK] already patched V25")
    raise SystemExit(0)

# (A) Mute spam line(s): any line containing "[VSP_DASH_FB] endpoints not found"
lines=s.splitlines(True)
out=[]
muted=0
for ln in lines:
    if "[VSP_DASH_FB] endpoints not found" in ln:
        # comment out safely (avoid systemd-style junk in the future too)
        out.append("# P3K26_V25_MUTED: " + ln)
        muted += 1
    else:
        out.append(ln)
s="".join(out)

# (B) Insert lazy-start helper (uses existing cachehot function if present)
# Ensure we have os/threading/time imported somewhere. We'll just add guarded imports in snippet.
snippet = f"""
# {TAG}
# Goal: avoid cachehot/warmup running at import-time (boot), start once on first request.
import os as _vsp_os
import threading as _vsp_threading
import time as _vsp_time

__vsp_cachehot_v25_started = False
__vsp_cachehot_v25_lock = _vsp_threading.Lock()

def __vsp_cachehot_v25_pick_runner():
    # best-effort: call whatever cachehot/warmup function exists
    for name in (
        "__vsp_cachehot", "_vsp_cachehot", "cachehot", "_cachehot",
        "warmup_cachehot", "_warmup_cachehot", "warmup_findings", "_warmup_findings",
        "cache_hot", "cache_hot_worker"
    ):
        fn = globals().get(name)
        if callable(fn):
            return fn
    return None

def __vsp_cachehot_v25_worker():
    try:
        delay = float(_vsp_os.environ.get("VSP_CACHEHOT_DELAY", "0.2") or "0.2")
    except Exception:
        delay = 0.2
    if delay > 0:
        _vsp_time.sleep(delay)

    fn = __vsp_cachehot_v25_pick_runner()
    if not callable(fn):
        return
    try:
        fn()
    except Exception:
        # keep boot/request stable; no crash
        return

def __vsp_cachehot_v25_start_once():
    global __vsp_cachehot_v25_started
    # default: lazy enabled, no boot start
    if _vsp_os.environ.get("VSP_CACHEHOT_DISABLE", "0") == "1":
        return
    if __vsp_cachehot_v25_started:
        return
    with __vsp_cachehot_v25_lock:
        if __vsp_cachehot_v25_started:
            return
        __vsp_cachehot_v25_started = True
        try:
            t = _vsp_threading.Thread(target=__vsp_cachehot_v25_worker, name="vsp-cachehot-v25", daemon=True)
            t.start()
        except Exception:
            __vsp_cachehot_v25_started = False
            return
"""

# Insert snippet near top (after initial imports / shebang area)
# We try to place it after the first block of imports (first blank line after imports),
# otherwise after the first 2000 chars.
m = re.search(r'(?ms)\A(.*?\n)(\s*\n)', s)
insert_at = None
if m:
    insert_at = m.end()
else:
    insert_at = min(len(s), 2000)
s = s[:insert_at] + snippet + s[insert_at:]

# (C) Stop starting cachehot at import-time (common pattern: Thread(...cachehot...).start())
# Make any Thread start that mentions cachehot/warmup conditional on env VSP_CACHEHOT_BOOT=1
# (default 0 => don't run at boot)
boot_guarded=0
new_lines=[]
for ln in s.splitlines(True):
    if (("Thread" in ln or "thread" in ln) and ".start(" in ln and
        ("cachehot" in ln.lower() or "warmup" in ln.lower() or "cache_hot" in ln.lower())):
        indent = re.match(r'^\s*', ln).group(0)
        new_lines.append(f'{indent}if _vsp_os.environ.get("VSP_CACHEHOT_BOOT","0") == "1":\n')
        new_lines.append(indent + "    " + ln.lstrip())
        boot_guarded += 1
    else:
        new_lines.append(ln)
s="".join(new_lines)

# (D) Kick lazy start on first request via WSGI entrypoint function def application(...)
# Insert __vsp_cachehot_v25_start_once() as first line inside application()
patched_app=0
m = re.search(r'(?m)^(def\s+application\s*\([^)]*\)\s*:\s*)$', s)
if m:
    # find line start index
    start = m.end()
    # insert after this line (next newline)
    nl = s.find("\n", start)
    if nl != -1:
        insert_pos = nl+1
        s = s[:insert_pos] + "    __vsp_cachehot_v25_start_once()\n" + s[insert_pos:]
        patched_app=1

# If no def application, try def wsgi_app
if not patched_app:
    m2 = re.search(r'(?m)^(def\s+wsgi_app\s*\([^)]*\)\s*:\s*)$', s)
    if m2:
        start = m2.end()
        nl = s.find("\n", start)
        if nl != -1:
            insert_pos = nl+1
            s = s[:insert_pos] + "    __vsp_cachehot_v25_start_once()\n" + s[insert_pos:]
            patched_app=1

p.write_text(s, encoding="utf-8")
print(f"[OK] V25 patched: muted={muted} boot_guarded={boot_guarded} kick_in_wsgi={patched_app}")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

# quick smoke (retry)
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for i in $(seq 1 20); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/api/vsp/rid_latest" >/dev/null 2>&1; then
    echo "[OK] smoke rid_latest try=$i"
    break
  fi
  sleep 0.2
done

echo "[DONE] p3k26_cachehot_lazy_and_mute_boot_logs_v25"
