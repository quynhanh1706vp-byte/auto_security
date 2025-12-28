#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl

TS="$(date +%Y%m%d_%H%M%S)"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_autoheal_${TS}"
echo "[BACKUP] ${W}.bak_autoheal_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile

w = Path("wsgi_vsp_ui_gateway.py")
lines = w.read_text(encoding="utf-8", errors="replace").splitlines(True)

def write():
    w.write_text("".join(lines), encoding="utf-8")

def compile_ok():
    py_compile.compile(str(w), doraise=True)

def patch_line(idx, reason):
    global lines
    if idx < 0 or idx >= len(lines): return False
    s = lines[idx]
    indent = s[:len(s)-len(s.lstrip(" \t"))]
    stripped = s.strip()

    # Case A: stray regex backref line starts with "\" (your current \1</html> case)
    if stripped.startswith("\\"):
        lines[idx] = indent + f"# VSP_AUTOHEAL_REMOVED_STRAY_BACKREF_V1 {stripped}\n"
        return True

    # Case B: stray HTML comment inside python
    if stripped.startswith("<!--") or "<!--" in stripped:
        lines[idx] = indent + "# VSP_AUTOHEAL_REMOVED_HTML_COMMENT_V1\n"
        return True

    # Case C: broken <script src="/static/js/..."> in a python double-quoted line
    if "<script" in s and 'src="/static/js/' in s:
        m = re.search(r'src="(/static/js/[^"]+)"', s)
        if m:
            src = m.group(1)
            suffix = "," if s.rstrip().endswith(",") else ""
            lines[idx] = indent + f"'  <script src=\"{src}\"></script>\\n'{suffix}\n"
            return True

    # Case D: line contains Jinja tokens inside python string
    if "{{" in s and "}}" in s and "<script" in s:
        # just drop the template token and keep plain src
        m = re.search(r'src="(/static/js/[^"?]+)', s)
        if m:
            src = m.group(1)
            suffix = "," if s.rstrip().endswith(",") else ""
            lines[idx] = indent + f"'  <script src=\"{src}\"></script>\\n'{suffix}\n"
            return True

    return False

# iterative heal
MAX = 12
for k in range(MAX):
    write()
    try:
        compile_ok()
        print(f"[OK] py_compile OK after {k} heal step(s)")
        break
    except Exception as e:
        msg = str(e)
        # try extract line number
        m = re.search(r'line\s+(\d+)', msg)
        if not m:
            print("[ERR] cannot parse line from error:", msg[:160])
            raise
        ln = int(m.group(1))
        idx = ln - 1
        bad = lines[idx].rstrip("\n") if 0 <= idx < len(lines) else "<out-of-range>"
        print(f"[DBG] heal step {k+1}: line {ln}: {bad[:120]}")
        if not patch_line(idx, msg):
            # also try patching previous line (sometimes the real culprit is above)
            if not patch_line(idx-1, msg):
                print("[ERR] autoheal cannot patch this error type. Show context:")
                lo = max(0, idx-8); hi = min(len(lines), idx+8)
                for j in range(lo, hi):
                    print(f"{j+1:6d} | {lines[j].rstrip()}")
                raise
else:
    raise SystemExit("[ERR] exceeded max heal iterations; file likely has deeper structural damage")

write()
PY

echo "== restart =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== sanity =="
curl -sS -I "$BASE/" | sed -n '1,8p' || true
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 220; echo

echo "[DONE] If service is up: hard reload /runs (Ctrl+Shift+R)."
