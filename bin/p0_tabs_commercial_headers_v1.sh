#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
W="wsgi_vsp_ui_gateway.py"
MARK="VSP_P0_TABS_COMMERCIAL_HEADERS_V1"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_hdr_${TS}"
echo "[BACKUP] ${W}.bak_hdr_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_TABS_COMMERCIAL_HEADERS_V1" in s:
    print("[SKIP] marker already present")
    raise SystemExit(0)

anchor = "# ===================== VSP_P1_EXPORT_HEAD_SUPPORT_WSGI_V1C ====================="
idx = s.find(anchor)
if idx < 0:
    idx = len(s)

patch = textwrap.dedent(r"""
# ===================== VSP_P0_TABS_COMMERCIAL_HEADERS_V1 =====================
# Add enterprise headers (security + cache) for 3 tabs (runs/data_source/settings) & static.
try:
    def _add_hdrs(path, status, headers):
        h = [(k, v) for (k, v) in headers if k and v]
        keys = {k.lower() for (k, _) in h}

        # Security headers (safe defaults)
        def put(k, v):
            lk = k.lower()
            nonlocal h, keys
            if lk not in keys:
                h.append((k, v)); keys.add(lk)

        put("X-Content-Type-Options", "nosniff")
        put("X-Frame-Options", "DENY")
        put("Referrer-Policy", "no-referrer")
        put("Permissions-Policy", "geolocation=(), microphone=(), camera=()")

        # Cache policy
        lp = (path or "").lower()
        is_static = lp.startswith("/static/") or lp.startswith("/out_ci/")
        if is_static:
            # allow caching static assets (browser side)
            # keep "no-store" away from static
            # only set if not already present
            if "cache-control" not in keys:
                h.append(("Cache-Control", "public, max-age=86400"))
        else:
            # HTML & API should not be cached by default
            # (avoid stale UI + security)
            if "cache-control" in keys:
                # keep existing if it's already no-store
                pass
            else:
                h.append(("Cache-Control", "no-store"))

        return h

    def _wrap_headers(inner):
        def _wsgi(environ, start_response):
            path = environ.get("PATH_INFO", "") or ""
            def _sr(status, headers, exc_info=None):
                headers2 = _add_hdrs(path, status, headers or [])
                return start_response(status, headers2, exc_info)
            return inner(environ, _sr)
        return _wsgi

    if "app" in globals() and callable(globals().get("app")):
        app = _wrap_headers(app)
    if "application" in globals() and callable(globals().get("application")):
        application = _wrap_headers(application)

    print("[VSP_P0_TABS_COMMERCIAL_HEADERS_V1] enabled")
except Exception as _e:
    print("[VSP_P0_TABS_COMMERCIAL_HEADERS_V1] ERROR:", _e)
# ===================== /VSP_P0_TABS_COMMERCIAL_HEADERS_V1 =====================
""")

p.write_text(s[:idx] + patch + "\n" + s[idx:], encoding="utf-8")
print("[OK] patched", p)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,14p' || true
fi

echo "[DONE]"
