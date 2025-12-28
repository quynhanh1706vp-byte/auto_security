#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_broken_${TS}"
echo "[SNAPSHOT BROKEN] ${WSGI}.bak_broken_${TS}"

echo "== find latest compiling backup =="
python3 - <<'PY'
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)

best = None
for b in baks[:80]:
    try:
        tmp = Path("/tmp/_vsp_wsgi_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        best = b
        break
    except Exception:
        continue

if not best:
    print("[ERR] no compiling backup found in last 80 backups")
    raise SystemExit(2)

print("[OK] best_backup =", best)
print(best.as_posix())
PY
BEST="$(python3 - <<'PY'
from pathlib import Path
import py_compile

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
for b in baks[:80]:
    try:
        tmp = Path("/tmp/_vsp_wsgi_try.py")
        tmp.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        py_compile.compile(str(tmp), doraise=True)
        print(b.as_posix())
        raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(2)
PY
)"

echo "[RESTORE] $BEST -> $WSGI"
cp -f "$BEST" "$WSGI"

echo "== apply sanitize (suffix-only) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P0_RELEASE_IDENTITY_EXPORTS_AFTERREQ_V1"
if MARK not in s:
    raise SystemExit("[ERR] marker not found; relid block missing")

# Replace __vsp_suffix(meta) with a safe version that sanitizes ts at suffix time
pat = r"def __vsp_suffix\(meta\):.*?^\s*def __vsp_rewrite_filename\(fn, meta\):"
m = re.search(pat, s, flags=re.S | re.M)
if not m:
    raise SystemExit("[ERR] cannot locate __vsp_suffix or next def __vsp_rewrite_filename")

new_suffix = r'''def __vsp_suffix(meta):
    # sanitize timestamp for filenames (avoid ':' '+' etc)
    ts_raw = (meta.get("release_ts") or "").strip()
    sha12 = meta.get("release_sha12") or "unknown"

    def _san(ts: str) -> str:
        t = (ts or "").strip()
        if not t:
            return ""
        # ISO-ish -> file-safe
        t = t.replace("T", "_")
        t = t.replace(":", "")
        t = t.replace("+", "p")   # +07:00 -> p0700
        # keep '-' (safe), remove other weird chars
        t = re.sub(r"[^0-9A-Za-z._-]+", "", t)
        return t

    ts = _san(ts_raw) or ("norel-" + __vsp_now_ts())

    if ts.startswith("norel-"):
        return f"_{ts}_sha-{sha12}"
    return f"_rel-{ts}_sha-{sha12}"

def __vsp_rewrite_filename(fn, meta):'''

s2 = s[:m.start()] + new_suffix + s[m.end():]
p.write_text(s2, encoding="utf-8")
print("[OK] sanitize suffix-only applied")
PY

echo "== compile check =="
python3 -m py_compile "$WSGI"

echo "== restart =="
systemctl restart "$SVC" 2>/dev/null || true

echo "[DONE] recovered + sanitize suffix-only OK"
