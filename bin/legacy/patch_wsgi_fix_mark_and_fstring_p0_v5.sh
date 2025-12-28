#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_mark_fstring_p0_v5_${TS}"
echo "[BACKUP] ${F}.bak_mark_fstring_p0_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARKER = "VSP_MARK_FIX_P0_V5"

# ---------- (A) Ensure MARK/MARK_B exist (fix NameError) ----------
if MARKER not in s:
    # insert after last import block (safe place)
    lines = s.splitlines(True)
    ins = 0

    # skip shebang/encoding + module docstring roughly
    i = 0
    if lines and lines[0].startswith("#!"):
        i += 1
    if i < len(lines) and "coding" in lines[i]:
        i += 1

    # try to pass initial docstring if present
    if i < len(lines) and re.match(r'^\s*[ruRU]{0,2}("""|\'\'\')', lines[i]):
        q = '"""' if '"""' in lines[i] else "'''"
        i += 1
        while i < len(lines) and q not in lines[i]:
            i += 1
        if i < len(lines):  # include closing line
            i += 1

    # now find last consecutive import/from line after that region
    j = i
    last_imp = -1
    while j < len(lines):
        if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', lines[j]):
            last_imp = j
            j += 1
            continue
        # allow blank lines and comments inside import area
        if last_imp >= 0 and (lines[j].strip() == "" or lines[j].lstrip().startswith("#")):
            j += 1
            continue
        break

    ins = (last_imp + 1) if last_imp >= 0 else i

    inject = (
        "\n# --- " + MARKER + " ---\n"
        "# Fix: prevent NameError for MARK used in HTML marker injection / fallbacks.\n"
        "if 'MARK' not in globals():\n"
        "    MARK = 'VSP_UI_GATEWAY_MARK_V1'\n"
        "MARK_B = (MARK.encode() if isinstance(MARK, str) else str(MARK).encode())\n"
        "# --- /" + MARKER + " ---\n\n"
    )
    lines.insert(ins, inject)
    s = "".join(lines)

# ---------- (B) Replace MARK.encode() -> MARK_B (avoid repeated encode + NameError) ----------
s2 = re.sub(r'\bMARK\.encode\(\)', 'MARK_B', s)
s = s2

# ---------- (C) Fix any orphan "f'" line that causes unterminated f-string ----------
# Common bad pattern:
#   html = (
#       f'
#       .....
#   )
# We convert the exact line that is only "f'" (optionally spaces) into f''' and try to close later.
# Minimal safe approach: convert ONLY standalone f' lines to f''' and also convert the first following
# standalone "'" line (same indent) to "'''".
lines = s.splitlines(True)
changed = False
for idx, line in enumerate(lines):
    if re.match(r'^\s*f\'\s*$', line):
        lines[idx] = re.sub(r"f'\s*$", "f'''", line)
        # find next line that is ONLY a single quote closing at same/greater indent
        base_indent = re.match(r'^(\s*)', line).group(1)
        k = idx + 1
        while k < len(lines):
            # stop if another string starts; keep it conservative
            if re.match(r'^\s*f[\'"]', lines[k]) and k != idx:
                break
            if re.match(r'^' + re.escape(base_indent) + r'\s*\'\s*$', lines[k]):
                lines[k] = re.sub(r"'\s*$", "'''", lines[k])
                break
            k += 1
        changed = True

if changed:
    s = "".join(lines)

# ---------- (D) Make _fallback not depend on f-strings or MARK existence ----------
# If there is a def _fallback(...) that references MARK, rewrite that function body safely.
pat = re.compile(r'(?ms)^(?P<ind>[ \t]*)def _fallback\((?P<sig>[^\n]*)\):\n(?P<body>(?:^(?P=ind)[ \t]+.*\n)+)')
m = pat.search(s)
if m and ("MARK" in m.group("body") or "Marker:" in m.group("body")):
    ind = m.group("ind")
    repl = (
        f"{ind}def _fallback({m.group('sig')}):\n"
        f"{ind}    # {MARKER}: safe fallback (no f-string pitfalls, no MARK NameError)\n"
        f"{ind}    try:\n"
        f"{ind}        marker = MARK\n"
        f"{ind}    except Exception:\n"
        f"{ind}        marker = 'VSP_UI_GATEWAY_MARK_V1'\n"
        f"{ind}    why_s = '' if why is None else str(why)\n"
        f"{ind}    html = (\n"
        f"{ind}        \"<!doctype html><meta charset='utf-8'>\"\n"
        f"{ind}        \"<title>VSP UI fallback</title>\"\n"
        f"{ind}        \"<pre>Marker: \" + str(marker) + \"\\n\" + why_s + \"</pre>\"\n"
        f"{ind}    )\n"
        f"{ind}    body = html.encode('utf-8', errors='replace')\n"
        f"{ind}    start_response('200 OK', [\n"
        f"{ind}        ('Content-Type','text/html; charset=utf-8'),\n"
        f"{ind}        ('Content-Length', str(len(body))),\n"
        f"{ind}        ('Cache-Control','no-store'),\n"
        f"{ind}    ])\n"
        f"{ind}    return [body]\n"
    )
    s = s[:m.start()] + repl + s[m.end():]

p.write_text(s, encoding="utf-8")
print("[OK] patched:", p)
PY

echo "== py_compile =="
python3 -m py_compile "$F" || {
  echo "[ERR] py_compile failed. Showing context..."
  python3 - <<'PY'
import traceback, sys
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace").splitlines()
# best-effort: print around any obvious 'f'' leftovers
for i,l in enumerate(s,1):
    if l.strip()=="f'" or l.strip().startswith("f'"):
        lo=max(1,i-6); hi=min(len(s), i+12)
        print(f"\n== suspicious around line {i} ==")
        for j in range(lo,hi+1):
            print(f"{j:5d}: {s[j-1]}")
PY
  exit 3
}

echo "== restart (systemd if available, else manual gunicorn) =="
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files | grep -q '^vsp-ui-8910.service'; then
  sudo systemctl restart vsp-ui-8910.service
  sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,70p' || true
else
  mkdir -p out_ci
  PIDF="out_ci/ui_8910.pid"

  # stop by pidfile
  if [ -f "$PIDF" ]; then
    PID="$(cat "$PIDF" 2>/dev/null || true)"
    [ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
  fi
  # stop by pkill
  pkill -f 'gunicorn .*8910' 2>/dev/null || true
  sleep 0.8
  rm -f "$PIDF" 2>/dev/null || true

  nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
    --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
    --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
    --bind 127.0.0.1:8910 --pid "$PIDF" \
    --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
    > out_ci/ui_8910.boot.log 2>&1 &

  # wait listen
  for i in 1 2 3 4 5 6; do
    ss -ltnp 2>/dev/null | grep -q ':8910' && break || true
    sleep 0.7
  done
fi

echo "== quick verify =="
curl -sS -I http://127.0.0.1:8910/ | sed -n '1,20p' || true
curl -sS -I http://127.0.0.1:8910/runs | sed -n '1,25p' || true

echo "== ensure no MARK NameError in tail =="
tail -n 260 out_ci/ui_8910.error.log 2>/dev/null | grep -n "NameError: name 'MARK' is not defined" && exit 4 || echo "[OK] no MARK NameError"
