#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v node >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
JS="static/js/vsp_tabs4_autorid_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_p2errtrap_${TS}"
echo "[BACKUP] ${JS}.bak_p2errtrap_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p = Path("static/js/vsp_tabs4_autorid_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

MARK_OPEN  = "/* VSP_P2_ERRTRAP_V1 */"
MARK_CLOSE = "/* /VSP_P2_ERRTRAP_V1 */"

if MARK_OPEN in s:
    print("[OK] marker exists: VSP_P2_ERRTRAP_V1 (skip)")
else:
    block = textwrap.dedent(r"""
    /* VSP_P2_ERRTRAP_V1 */
    (() => {
      if (window.__VSP_ERRTRAP_INSTALLED__) return;
      window.__VSP_ERRTRAP_INSTALLED__ = true;

      const debug = (() => {
        try {
          if (/[?&]debug=1\b/.test(location.search)) return true;
          const v = localStorage.getItem('vsp_debug');
          return v === '1' || v === 'true';
        } catch (e) { return false; }
      })();

      const orig = {
        log: console.log ? console.log.bind(console) : ()=>{},
        info: console.info ? console.info.bind(console) : ()=>{},
        debug: console.debug ? console.debug.bind(console) : ()=>{},
        warn: console.warn ? console.warn.bind(console) : ()=>{},
        error: console.error ? console.error.bind(console) : ()=>{},
      };

      // Commercial default: keep warn/error only (reduce noise)
      if (!debug) {
        try {
          console.log = () => {};
          console.info = () => {};
          console.debug = () => {};
        } catch (e) {}
      }

      function ctx() {
        let rid = '';
        try { rid = new URLSearchParams(location.search).get('rid') || ''; } catch (e) {}
        if (!rid && window.VSP_RID) rid = String(window.VSP_RID);
        if (!rid) {
          try { rid = localStorage.getItem('vsp_rid_latest') || ''; } catch (e) {}
        }
        const tab = (location.pathname || '').replace(/\/+$/,'') || '/';
        return { rid, tab, url: location.href };
      }

      function emit(kind, msg) {
        const c = ctx();
        const m = (msg || '').toString().replace(/\s+/g,' ').slice(0, 220);
        orig.error(`[VSP_UI_ERR] ${kind} tab=${c.tab} rid=${c.rid || '-'} msg=${m}`);
      }

      // window.onerror (capture)
      window.addEventListener('error', (ev) => {
        try {
          const m = (ev && ev.message) ? ev.message : 'error';
          emit('error', m);
        } catch (e) {}
      }, true);

      // Promise rejection
      window.addEventListener('unhandledrejection', (ev) => {
        try {
          let msg = 'unhandledrejection';
          const r = ev && ev.reason;
          if (typeof r === 'string') msg = r;
          else if (r && r.message) msg = r.message;
          else {
            try { msg = JSON.stringify(r); } catch (e) { msg = String(r); }
          }
          emit('unhandledrejection', msg);
        } catch (e) {}
      });
    })();
    /* /VSP_P2_ERRTRAP_V1 */
    """).strip("\n") + "\n"

    p.write_text(s.rstrip() + "\n\n" + block, encoding="utf-8")
    print("[OK] appended VSP_P2_ERRTRAP_V1 into", str(p))
PY

if command -v node >/dev/null 2>&1; then
  node --check "$JS" >/dev/null
  echo "[OK] node --check $JS"
else
  echo "[WARN] node not found; skipped JS syntax check"
fi

systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted $SVC (if present)"
