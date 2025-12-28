#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_broken_snapshot_${TS}"
echo "[SNAPSHOT] ${W}.bak_broken_snapshot_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile, shutil, re, time

W = Path("wsgi_vsp_ui_gateway.py")
MARK = "VSP_P2_INJECT_BUNDLE_TABS5_WSGI_V1"

def compiles(path: Path) -> bool:
    try:
        py_compile.compile(str(path), doraise=True)
        return True
    except Exception:
        return False

# 1) If current is broken, auto-restore newest compiling backup
if not compiles(W):
    baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
    good = None
    for b in baks:
        if compiles(b):
            good = b
            break
    if not good:
        raise SystemExit("[ERR] no compiling backup found. Check your backups list: ls -1t wsgi_vsp_ui_gateway.py.bak_* | head")
    shutil.copy2(good, W)
    print("[RESTORE] restored compiling backup:", good.name)
else:
    print("[OK] current wsgi compiles")

s = W.read_text(encoding="utf-8", errors="ignore")

start = f"# ===================== {MARK} ====================="
end   = f"# ===================== /{MARK} ====================="

# 2) Prepare a SAFE block (escape \\n is kept as characters in target file)
safe_block = f"""
# ===================== {MARK} =====================
# Ensure tabs5 bundle exists for main 5 pages, independent of templates.
try:
    from flask import request
    import re as _re
    import time as _time

    _VSP_P2_BUNDLE_FALLBACK_V = str(int(_time.time()))

    @app.after_request
    def _vsp_p2_inject_bundle_tabs5(resp):
        try:
            path = getattr(request, "path", "") or ""
            if path == "/":
                path = "/vsp5"
            if path not in ("/vsp5","/runs","/settings","/data_source","/rule_overrides"):
                return resp

            # Some responses may be passthrough/streaming-like; force readable body
            try:
                if hasattr(resp, "direct_passthrough") and getattr(resp, "direct_passthrough", False):
                    resp.direct_passthrough = False
            except Exception:
                pass

            ct = (resp.headers.get("Content-Type","") or "").lower()
            mt = (getattr(resp, "mimetype", "") or "").lower()
            if ("text/html" not in ct) and (mt != "text/html"):
                return resp

            body = resp.get_data(as_text=True)  # type: ignore
            if "vsp_bundle_tabs5_v1.js" in body:
                try: resp.headers["X-VSP-P2-BUNDLE"] = "present"
                except Exception: pass
                return resp

            mm = _re.search(r'vsp_tabs4_autorid_v1\\.js\\?v=([0-9]{{6,}})', body)
            v = mm.group(1) if mm else _VSP_P2_BUNDLE_FALLBACK_V

            tag = f'<script defer src="/static/js/vsp_bundle_tabs5_v1.js?v={{v}}"></script>'

            if "</body>" in body:
                body = body.replace("</body>", tag + "\\\\n</body>", 1)
            elif "</head>" in body:
                body = body.replace("</head>", tag + "\\\\n</head>", 1)
            else:
                body = body + "\\\\n" + tag + "\\\\n"

            resp.set_data(body)  # type: ignore
            resp.headers["Content-Length"] = str(len(body.encode("utf-8")))
            try: resp.headers["X-VSP-P2-BUNDLE"] = "injected"
            except Exception: pass
            return resp
        except Exception:
            try: resp.headers["X-VSP-P2-BUNDLE"] = "err"
            except Exception: pass
            return resp
except Exception:
    pass
# ===================== /{MARK} =====================
""".lstrip("\n").rstrip("\n")

# 3) Replace existing marker block if present, else insert after `app = application`
if start in s and end in s:
    pat = re.compile(re.escape(start) + r".*?" + re.escape(end), flags=re.S)
    s2, n = pat.subn(safe_block, s, count=1)
    if n != 1:
        raise SystemExit(f"[ERR] failed to replace marker block: replaced={n}")
    s = s2
    print("[OK] replaced existing marker block")
else:
    m = re.search(r'(^\s*app\s*=\s*application\s*$)', s, flags=re.M)
    if not m:
        raise SystemExit("[ERR] cannot find anchor line `app = application` to insert block")
    pos = m.end(1)
    s = s[:pos] + "\n\n" + safe_block + "\n\n" + s[pos:]
    print("[OK] inserted marker block after `app = application`")

W.write_text(s, encoding="utf-8")
py_compile.compile(str(W), doraise=True)
print("[OK] final wsgi compiles")
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== [SELF-CHECK] /vsp5 header + bundle =="
curl -fsS -I "$BASE/vsp5" | egrep -i 'HTTP/|Content-Type|X-VSP-P2-BUNDLE|Content-Length|Server' || true

H="$(curl -fsS "$BASE/vsp5")"
echo "$H" | grep -q "vsp_tabs4_autorid_v1.js" || { echo "[ERR] missing autorid on /vsp5"; exit 3; }
echo "$H" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on /vsp5"; exit 3; }
echo "[OK] bundle present on /vsp5"

echo "== [SELF-CHECK] 5 pages have bundle =="
for P in /vsp5 /runs /settings /data_source /rule_overrides; do
  HTML="$(curl -fsS "$BASE$P")"
  echo "$HTML" | grep -q "vsp_bundle_tabs5_v1.js" || { echo "[ERR] missing bundle on $P"; exit 3; }
  echo "[OK] $P"
done

echo "[DONE] P2 bundle inject (WSGI) rescued + fixed"
