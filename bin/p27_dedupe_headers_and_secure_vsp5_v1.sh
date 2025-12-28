#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_p27_${TS}"
echo "[BACKUP] ${F}.bak_p27_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P27_HEADERS_DEDUPE_AND_SECURE_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    sys.exit(0)

# Append a final WSGI wrapper that:
# 1) dedupes unsafe-to-duplicate headers (CSP-RO, AUTORID, security headers)
# 2) ensures security headers exist for HTML (esp /vsp5 which bypasses Flask after_request)
block = r'''
# ===================== VSP_P27_HEADERS_DEDUPE_AND_SECURE_V1 =====================
# Commercial-safe: final WSGI wrapper to dedupe headers and ensure security headers on HTML tabs.
try:
    def _vsp_p27__get_header(_hs, _name_lower):
        for _k, _v in _hs or []:
            try:
                if (_k or "").lower() == _name_lower:
                    return _v
            except Exception:
                pass
        return None

    def _vsp_p27__has_header(_hs, _name_lower):
        return _vsp_p27__get_header(_hs, _name_lower) is not None

    def _vsp_p27__dedupe_headers(_hs):
        # Only dedupe specific headers that must be singletons for "commercial clean".
        DEDUPE = {
            "content-security-policy",
            "content-security-policy-report-only",
            "x-vsp-autorid-inject",
            "x-content-type-options",
            "x-frame-options",
            "referrer-policy",
            "permissions-policy",
            "x-xss-protection",
            "pragma",
            "expires",
            "x-vsp-markers-mw",
            "x-vsp-markers-final",
        }
        out_rev = []
        seen = set()
        for _k, _v in reversed(_hs or []):
            try:
                _kl = (_k or "").lower()
            except Exception:
                _kl = ""
            if _kl in DEDUPE:
                if _kl in seen:
                    continue
                seen.add(_kl)
            out_rev.append((_k, _v))
        return list(reversed(out_rev))

    def _vsp_p27__ensure_security_headers(_hs, _environ=None):
        # Apply only to HTML to avoid surprising API clients.
        ct = (_vsp_p27__get_header(_hs, "content-type") or "")
        is_html = str(ct).lower().startswith("text/html")
        if not is_html:
            return _hs

        # Minimal, widely-safe security headers (do not break JS/CSS because CSP is Report-Only).
        if not _vsp_p27__has_header(_hs, "x-content-type-options"):
            _hs.append(("X-Content-Type-Options", "nosniff"))
        if not _vsp_p27__has_header(_hs, "x-frame-options"):
            _hs.append(("X-Frame-Options", "DENY"))
        if not _vsp_p27__has_header(_hs, "referrer-policy"):
            _hs.append(("Referrer-Policy", "no-referrer"))
        if not _vsp_p27__has_header(_hs, "permissions-policy"):
            _hs.append(("Permissions-Policy", "camera=(), microphone=(), geolocation=(), payment=(), usb=(), interest-cohort=()"))

        # Ensure CSP Report-Only exists exactly once (dedupe will enforce singleton).
        # If earlier layers already set it, we don't overwrite.
        if not _vsp_p27__has_header(_hs, "content-security-policy-report-only"):
            _CSP_RO = "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; " \
                      "script-src 'self' 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"
            _hs.append(("Content-Security-Policy-Report-Only", _CSP_RO))

        return _hs

    def _vsp_p27__wrap_wsgi(_wsgi_app):
        if not callable(_wsgi_app):
            return _wsgi_app

        def _app(environ, start_response):
            def _sr(status, headers, exc_info=None):
                try:
                    hs = list(headers or [])
                except Exception:
                    hs = []
                try:
                    hs = _vsp_p27__ensure_security_headers(hs, environ)
                    hs = _vsp_p27__dedupe_headers(hs)
                except Exception:
                    # never break response on header hardening
                    pass
                return start_response(status, hs, exc_info)
            return _wsgi_app(environ, _sr)

        try:
            _app.__name__ = getattr(_wsgi_app, "__name__", "application") + "_vsp_p27"
        except Exception:
            pass
        return _app

    # Wrap the final exposed WSGI callable(s) once.
    # Gunicorn typically uses `application`. Some setups may use `app` or gateway aliases.
    if "application" in globals() and callable(globals().get("application")):
        _orig = globals()["application"]
        globals()["application"] = _vsp_p27__wrap_wsgi(_orig)

    if "app" in globals() and callable(globals().get("app")):
        # If app is a Flask WSGI app, wrapping is harmless; if it's not WSGI, wrapper keeps it callable-safe.
        _orig2 = globals()["app"]
        globals()["app"] = _vsp_p27__wrap_wsgi(_orig2)

    print("[VSP_P27] installed header dedupe + html security headers")
except Exception as _e:
    print("[VSP_P27] ERROR:", _e)
# ===================== /VSP_P27_HEADERS_DEDUPE_AND_SECURE_V1 =====================
'''

s2 = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s2, encoding="utf-8")

# compile check
py_compile.compile(str(p), doraise=True)
print("[OK] patched + py_compile OK")
PY

echo "== [CHECK] py_compile =="
python3 -m py_compile "$F"

if command -v systemctl >/dev/null 2>&1; then
  echo "== [RESTART] $SVC =="
  sudo systemctl restart "$SVC"
  sudo systemctl --no-pager --full status "$SVC" | head -n 20 || true
else
  echo "[WARN] systemctl not found; restart service manually"
fi

echo "== [WAIT] wait port =="
for i in $(seq 1 30); do
  if curl -fsS -o /dev/null "${BASE:-http://127.0.0.1:8910}/vsp5" >/dev/null 2>&1; then
    echo "[OK] UI ready"
    break
  fi
  sleep 0.2
done
echo "== [SMOKE] header dedupe check =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  echo "--- $p"
  curl -fsS -o /dev/null -D- "$BASE$p" \
    | awk 'BEGIN{IGNORECASE=1}
           /^Content-Security-Policy-Report-Only:/ {csp++}
           /^X-VSP-AUTORID-INJECT:/ {rid++}
           /^X-Content-Type-Options:/ {nosniff++}
           /^X-Frame-Options:/ {xfo++}
           /^Referrer-Policy:/ {rp++}
           /^Permissions-Policy:/ {pp++}
           END{printf("counts: CSP_RO=%d AUTORID=%d nosniff=%d xfo=%d refpol=%d perm=%d\n", csp+0,rid+0,nosniff+0,xfo+0,rp+0,pp+0)}'
done
