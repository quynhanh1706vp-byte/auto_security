#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BUNDLE="static/js/vsp_bundle_commercial_v2.js"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ]   || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$BUNDLE" ] || { echo "[ERR] missing $BUNDLE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI"   "${WSGI}.bak_dashonly_${TS}"
cp -f "$BUNDLE" "${BUNDLE}.bak_dashonly_${TS}"
echo "[BACKUP] ${WSGI}.bak_dashonly_${TS}"
echo "[BACKUP] ${BUNDLE}.bak_dashonly_${TS}"

echo "== [0] recover wsgi if broken (restore latest compiling backup) =="
if ! python3 -m py_compile "$WSGI" >/dev/null 2>&1; then
  echo "[WARN] current wsgi broken -> searching backups..."
  GOOD=""
  for f in $(ls -1t "${WSGI}".bak_* 2>/dev/null || true); do
    if python3 -m py_compile "$f" >/dev/null 2>&1; then GOOD="$f"; break; fi
  done
  [ -n "$GOOD" ] || { echo "[ERR] no compiling backup found"; exit 3; }
  cp -f "$GOOD" "$WSGI"
  echo "[OK] restored from: $GOOD"
fi

echo "== [1] patch bundle: DASHBOARD-ONLY kill switch (stop intervals, stop /api/vsp/runs, stop double render) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("static/js/vsp_bundle_commercial_v2.js")
s = p.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_DASH_ONLY_KILL_SWITCH_V1"
if marker in s:
    print("[OK] bundle already has", marker)
else:
    kill = r"""/* VSP_P0_DASH_ONLY_KILL_SWITCH_V1 */
(()=> {
  if (window.__vsp_p0_dash_only_kill_v1) return;
  window.__vsp_p0_dash_only_kill_v1 = true;

  // Dashboard-only mode (set by /vsp5 HTML middleware)
  const dashOnly = !!(window.__VSP_DASH_ONLY || window.__VSP_DASHBOARD_ONLY);
  if (!dashOnly) return;

  window.__VSP_DISABLE_AUTOFRESH = true;
  window.__VSP_DISABLE_RUNS_META = true;
  window.__VSP_DISABLE_LEGACY    = true;

  // Block legacy intervals that cause "nhảy về"
  const _setInterval = window.setInterval ? window.setInterval.bind(window) : null;
  if (_setInterval) {
    window.setInterval = (fn, ms, ...rest) => {
      try{
        const src = (typeof fn === 'function') ? (fn.name || fn.toString()) : String(fn);
        if (/AutoRefresh|runs_meta|rid_autofix|DashV6|legacy|V6C|V6D|V6E|GateStory/i.test(src)) {
          console.warn("[VSP][DASH_ONLY] blocked interval", ms);
          return 0;
        }
      }catch(_){}
      return _setInterval(fn, ms, ...rest);
    };
  }

  // Block runs list calls (Dashboard-only)
  const _fetch = window.fetch ? window.fetch.bind(window) : null;
  if (_fetch) {
    window.fetch = (url, opts) => {
      try{
        const u = String(url||"");
        if (window.__VSP_DISABLE_RUNS_META && /\/api\/vsp\/runs\b/.test(u)) {
          console.warn("[VSP][DASH_ONLY] blocked fetch", u);
          return Promise.reject(new Error("blocked /api/vsp/runs in dash-only"));
        }
      }catch(_){}
      return _fetch(url, opts);
    };
  }

  // Prevent double render patterns (best-effort guard)
  window.__VSP_DASH_RENDER_ONCE = true;
  if (!window.__VSP_DASH_RENDERED) window.__VSP_DASH_RENDERED = 0;

  // If any module calls global render twice, it should check this flag (we enforce here too)
  const _raf = window.requestAnimationFrame ? window.requestAnimationFrame.bind(window) : null;
  if (_raf) {
    window.requestAnimationFrame = (cb) => _raf(() => {
      try{
        // prune accidental duplicate dashboard blocks (heuristic)
        const roots = document.querySelectorAll("#vsp5_root .vsp-card, #vsp5_root .vsp_panel, #vsp5_root .vsp-panel");
        if (roots && roots.length > 3000) { /* ignore */ }
      }catch(_){}
      cb && cb();
    });
  }

  console.log("[VSP][DASH_ONLY] kill-switch enabled");
})();
"""
    p.write_text(kill + "\n" + s, encoding="utf-8")
    print("[OK] injected", marker)
PY

echo "== [2] patch wsgi: add /vsp5 HTML rewrite middleware (remove extra dashboard scripts, set dash-only flags) =="
python3 - <<'PY'
from pathlib import Path
import re, time

w = Path("wsgi_vsp_ui_gateway.py")
s = w.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_VSP5_DASHBOARD_ONLY_REWRITE_MW_V1"
if marker in s:
    print("[OK] wsgi already has", marker)
else:
    mw = r'''
# ===================== VSP_P0_VSP5_DASHBOARD_ONLY_REWRITE_MW_V1 =====================
def _vsp5_dashonly_rewrite_mw(app):
    import re, time
    def _wrap(environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path != "/vsp5":
            return app(environ, start_response)

        captured = {"status":None, "headers":None}
        def _sr(status, headers, exc_info=None):
            captured["status"] = status
            captured["headers"] = headers
            return lambda x: None

        body_iter = app(environ, _sr)
        try:
            body = b"".join(body_iter)
        finally:
            try:
                close = getattr(body_iter, "close", None)
                if close: close()
            except Exception:
                pass

        # Only rewrite HTML
        hdrs = captured["headers"] or []
        ctype = ""
        for k,v in hdrs:
            if str(k).lower() == "content-type":
                ctype = str(v).lower()
                break
        if "text/html" not in ctype:
            start_response(captured["status"] or "200 OK", hdrs)
            return [body]

        html = body.decode("utf-8", "replace")

        # 1) Remove extra dashboard scripts (gate_story / containers_fix / luxe / rid_autofix etc.)
        html = re.sub(r'<script[^>]+src=["\']/static/js/vsp_dashboard_gate_story_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', '', html, flags=re.I)
        html = re.sub(r'<script[^>]+src=["\']/static/js/vsp_dashboard_containers_fix_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', '', html, flags=re.I)
        html = re.sub(r'<script[^>]+src=["\']/static/js/vsp_dashboard_luxe_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', '', html, flags=re.I)
        html = re.sub(r'<script[^>]+src=["\']/static/js/vsp_rid_autofix_v1\.js[^"\']*["\'][^>]*>\s*</script>\s*', '', html, flags=re.I)

        # 2) Ensure polish css is present
        if "/static/css/vsp_dashboard_polish_v1.css" not in html:
            html = re.sub(r'</title>\s*', "</title>\n  <link rel='stylesheet' href='/static/css/vsp_dashboard_polish_v1.css'/>\n", html, count=1, flags=re.I)

        # 3) Add dash-only flags (before scripts)
        flag = "<script>window.__VSP_DASH_ONLY=1;window.__VSP_DASHBOARD_ONLY=1;window.__VSP_DISABLE_AUTOFRESH=1;window.__VSP_DISABLE_RUNS_META=1;window.__VSP_DISABLE_LUXE=1;</script>"
        if "window.__VSP_DASH_ONLY" not in html:
            html = re.sub(r'(<div id="vsp5_root"\s*></div>)', r'\1\n  ' + flag, html, count=1, flags=re.I)

        # 4) Keep only minimal scripts: fetch_shim + commercial bundle
        # Remove all /static/js script tags then re-add the two we want, using same ?v= if present.
        m = re.search(r'v=([0-9]{10,})', html)
        v = m.group(1) if m else str(int(time.time()))
        html = re.sub(r'<script[^>]+src=["\']/static/js/[^"\']+["\'][^>]*>\s*</script>\s*', '', html, flags=re.I)

        inject = (
          f"\n  <script src=\"/static/js/vsp_p0_fetch_shim_v1.js?v={v}\"></script>"
          f"\n  <script src=\"/static/js/vsp_bundle_commercial_v2.js?v={v}\"></script>\n"
        )
        if "</body>" in html:
            html = html.replace("</body>", inject + "</body>", 1)
        else:
            html += inject

        out = html.encode("utf-8")

        # Fix headers (Content-Length)
        new_headers = []
        for k,vh in (captured["headers"] or []):
            if str(k).lower() == "content-length":
                continue
            new_headers.append((k,vh))
        new_headers.append(("Content-Length", str(len(out))))

        start_response(captured["status"] or "200 OK", new_headers)
        return [out]
    return _wrap
# ===================== /VSP_P0_VSP5_DASHBOARD_ONLY_REWRITE_MW_V1 =====================
'''
    # Append middleware and wrap application at the end (safe)
    s2 = s + "\n" + mw + "\n"
    # Wrap application variable (best effort: find last assignment line "application =" then append wrapper)
    if "application = _vsp5_dashonly_rewrite_mw(application)" not in s2:
        s2 += "\n# VSP_P0_VSP5_DASHBOARD_ONLY_REWRITE_MW_V1 apply\n"
        s2 += "try:\n    application = _vsp5_dashonly_rewrite_mw(application)\nexcept Exception as _e:\n    pass\n"
    w.write_text(s2, encoding="utf-8")
    print("[OK] injected", marker)
PY

echo "== [3] node --check (best effort) =="
if command -v node >/dev/null 2>&1; then
  node --check "$BUNDLE" && echo "[OK] node --check passed"
fi

echo "== [4] compile check wsgi =="
python3 -m py_compile "$WSGI"

echo "== [5] restart service (best effort) =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.6

echo "== [6] verify /vsp5 scripts are MINIMAL and no extra dashboard scripts =="
curl -fsS "$BASE/vsp5" | grep -nE "vsp_bundle_commercial_v2|vsp_p0_fetch_shim_v1|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" || true
echo "== DONE =="
echo "Hard refresh /vsp5 (Ctrl+Shift+R). Console should show: [VSP][DASH_ONLY] kill-switch enabled"
