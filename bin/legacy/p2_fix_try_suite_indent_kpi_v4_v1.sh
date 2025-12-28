#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }
cp -f "$F" "${F}.bak_trysuite_${TS}"
echo "[BACKUP] ${F}.bak_trysuite_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("wsgi_vsp_ui_gateway.py")
lines = p.read_text(errors="ignore").splitlines(True)

def lws(s: str) -> str:
    m = re.match(r'^([ \t]*)', s)
    return m.group(1) if m else ""

changed = 0
# We only touch very-local blocks that look like our KPI_V4 patches:
#   try:
#       import os as _os
#   if _os.environ.get(...):
# (=> indent the stray 'if/else/print' lines back inside the try suite)
for i in range(len(lines)):
    if not re.match(r'^[ \t]*try:\s*(#.*)?\s*$', lines[i].rstrip("\n")):
        continue

    try_ws = lws(lines[i])
    inner_ws = try_ws + "    "

    # only consider nearby blocks (avoid damaging other logic)
    # Look ahead up to 60 lines for an 'import os as _os' which indicates our injected block
    jmax = min(len(lines), i + 60)
    has_os_import = False
    for j in range(i+1, jmax):
        if re.match(r'^[ \t]*import\s+os\s+as\s+_os\b', lines[j].rstrip("\n")):
            has_os_import = True
            break
        # stop if we exit indentation scope too early
        if lws(lines[j]) < try_ws and lines[j].strip():
            break
    if not has_os_import:
        continue

    # Now re-indent any line between try: and the next except/finally at try_ws
    # that accidentally sits at try_ws (same indent as try) but is NOT except/finally.
    for k in range(i+1, jmax):
        txt = lines[k].rstrip("\n")
        if not txt.strip():
            continue

        ws = lws(lines[k])

        # stop when hitting except/finally aligned with try
        if ws == try_ws and re.match(r'^(except\b|finally\b)', txt.strip()):
            break

        # only fix "stray" lines exactly aligned with try (typical: if/else/print)
        if ws == try_ws and not re.match(r'^(except\b|finally\b)', txt.strip()):
            lines[k] = inner_ws + lines[k].lstrip(" \t")
            changed += 1

p.write_text("".join(lines), encoding="utf-8")
print("[OK] reindented stray lines inside try-suite =", changed)

py_compile.compile(str(p), doraise=True)
print("[OK] py_compile OK")
PY

echo "== restart service =="
sudo systemctl daemon-reload || true
sudo systemctl restart "$SVC" || true
sleep 0.5
sudo systemctl status "$SVC" -l --no-pager || true

echo "== if still fail, show real tail (avoid curl spam) =="
sudo journalctl -u "$SVC" -n 80 --no-pager | tail -n 80
