#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need awk; need sort; need head

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*"; }
err(){ echo "[ERR] $*"; }

[ -f "$W" ] || { err "missing $W"; exit 2; }
cp -f "$W" "${W}.bak_p110_fix_${TS}"
ok "backup: ${W}.bak_p110_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

MARK="VSP_P110_STATIC_CACHE_BYPASS_V1"
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

if MARK in s:
    print("[OK] marker found: already patched")
    raise SystemExit(0)

patch = r'''
# === __MARK__ ===
# Fast-path /static/*: bypass heavy middleware chain + send immutable cache headers
# You already use ?v=... so long cache is safe.
import os, mimetypes, email.utils, time

def _vsp_p110_httpdate(ts: float) -> str:
    return email.utils.formatdate(ts, usegmt=True)

def _vsp_p110_safe_join(root: str, rel: str) -> str:
    rel = (rel or "").lstrip("/").replace("\\", "/")
    parts = [x for x in rel.split("/") if x not in ("", ".", "..")]
    return os.path.join(root, *parts)

class _VSP_P110_StaticBypass:
    def __init__(self, app, static_dir: str, cache_seconds: int = 31536000):
        self.app = app
        self.static_dir = static_dir
        self.cache_seconds = int(cache_seconds)

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO", "") or ""
            if not path.startswith("/static/"):
                return self.app(environ, start_response)

            if os.environ.get("VSP_P110_STATIC_BYPASS", "1") in ("0","false","False"):
                return self.app(environ, start_response)

            rel = path[len("/static/"):]
            fpath = _vsp_p110_safe_join(self.static_dir, rel)

            if (not os.path.isfile(fpath)) or (not os.path.realpath(fpath).startswith(os.path.realpath(self.static_dir))):
                return self.app(environ, start_response)

            st = os.stat(fpath)
            mtime, size = st.st_mtime, st.st_size
            etag = f'W/"{int(mtime)}-{size}"'

            inm = environ.get("HTTP_IF_NONE_MATCH")
            if inm and etag in inm:
                hdrs = [
                    ("ETag", etag),
                    ("Cache-Control", f"public, max-age={self.cache_seconds}, immutable"),
                    ("Last-Modified", _vsp_p110_httpdate(mtime)),
                    ("Expires", _vsp_p110_httpdate(time.time() + self.cache_seconds)),
                ]
                start_response("304 Not Modified", hdrs)
                return [b""]

            ctype, _enc = mimetypes.guess_type(fpath)
            if not ctype:
                ctype = "application/octet-stream"

            hdrs = [
                ("Content-Type", ctype),
                ("Content-Length", str(size)),
                ("ETag", etag),
                ("Cache-Control", f"public, max-age={self.cache_seconds}, immutable"),
                ("Last-Modified", _vsp_p110_httpdate(mtime)),
                ("Expires", _vsp_p110_httpdate(time.time() + self.cache_seconds)),
            ]

            start_response("200 OK", hdrs)
            with open(fpath, "rb") as f:
                return [f.read()]
        except Exception:
            return self.app(environ, start_response)

def _vsp_p110_install():
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        static_dir = os.path.join(here, "static")
        if not os.path.isdir(static_dir):
            return False
        g = globals()
        if "application" in g and callable(g.get("application")):
            g["application"] = _VSP_P110_StaticBypass(g["application"], static_dir)
            return True
        if "app" in g:
            a = g.get("app")
            if hasattr(a, "wsgi_app") and callable(getattr(a, "wsgi_app")):
                a.wsgi_app = _VSP_P110_StaticBypass(a.wsgi_app, static_dir)
                return True
        return False
    except Exception:
        return False

_VSP_P110_INSTALLED = _vsp_p110_install()
# === /__MARK__ ===
'''.strip("\n").replace("__MARK__", MARK)

m = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', s)
if m:
    s2 = s[:m.start()] + "\n\n" + patch + "\n\n" + s[m.start():]
else:
    s2 = s + "\n\n" + patch + "\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched wsgi_vsp_ui_gateway.py (P110 installed)")
PY

python3 -m py_compile "$W" >/dev/null 2>&1 || { err "py_compile failed"; exit 3; }
ok "py_compile ok"

if command -v systemctl >/dev/null 2>&1 && systemctl status "$SVC" >/dev/null 2>&1; then
  ok "restart service: $SVC"
  sudo systemctl restart "$SVC"
  sleep 1
else
  warn "skip restart (no systemctl or service not found): $SVC"
fi

# Warm
for i in 1 2 3; do curl -fsS --connect-timeout 2 --max-time 8 "$BASE/vsp5" -o /dev/null || true; done

assets=(
  "/static/js/vsp_bundle_tabs5_v1.js"
  "/static/js/vsp_dashboard_live_v2.js"
  "/static/css/vsp_2025_dark.css"
)

echo "== [P110] Static header check =="
for a in "${assets[@]}"; do
  echo "-- $a --"
  curl -fsS -D- -o /dev/null --connect-timeout 2 --max-time 10 "$BASE$a?v=$TS" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Cache-Control:|^ETag:|^Last-Modified:|^Expires:/{print}'
done

measure(){ curl -sS -o /dev/null --connect-timeout 2 --max-time 20 -w "%{time_total}\n" "$1" || echo 999; }
median3(){ sort -n | awk 'NR==2{print;exit}'; }

echo
echo "== [P110] Perf measure (median of 3) =="

static_meds=()
for a in "${assets[@]}"; do
  echo "-- static $a --"
  med="$( { measure "$BASE$a?v=$TS"; measure "$BASE$a?v=$TS"; measure "$BASE$a?v=$TS"; } | median3 )"
  echo "median_static_sec $a $med"
  static_meds+=("$med")
done
static_overall="$(printf "%s\n" "${static_meds[@]}" | median3)"
echo "[STAT] static_overall_median_sec=$static_overall"

tabs=(/vsp5 /runs /data_source /settings /rule_overrides)
tab_meds=()
for t in "${tabs[@]}"; do
  echo "-- tab $t --"
  med="$( { measure "$BASE$t"; measure "$BASE$t"; measure "$BASE$t"; } | median3 )"
  echo "median_tab_sec $t $med"
  tab_meds+=("$med")
done
tab_overall="$(printf "%s\n" "${tab_meds[@]}" | median3)"
echo "[STAT] tab_overall_median_sec=$tab_overall"

verdict_static="$(python3 - <<PY
s=float("$static_overall")
print("GREEN" if s<=0.20 else ("AMBER" if s<=0.50 else "RED"))
PY
)"
verdict_tabs="$(python3 - <<PY
t=float("$tab_overall")
print("GREEN" if t<=1.0 else ("AMBER" if t<=2.0 else "RED"))
PY
)"

echo
echo "== [P110] VERDICT =="
echo "static: $verdict_static (median=${static_overall}s)"
echo "tabs:   $verdict_tabs   (median=${tab_overall}s)"

echo
echo "Note: disable bypass temporarily: export VSP_P110_STATIC_BYPASS=0 (then restart service)"
