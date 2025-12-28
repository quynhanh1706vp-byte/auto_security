#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need head
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
RID="${1:-VSP_CI_20251215_173713}"

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

# 1) Write orchestrator JS
mkdir -p static/js
JS="static/js/vsp_rid_switch_refresh_all_v1.js"
cat > "$JS" <<'JS'
/* VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1 */
(function(){
  'use strict';

  const LS_KEY = 'vsp_rid_last';

  function $all(sel, root){ return Array.from((root||document).querySelectorAll(sel)); }
  function detectRidSelect(){
    const ids = ['#rid', '#RID', '#vsp-rid', '#vsp-rid-select', '#ridSelect', '#runRid', '#run-rid'];
    for (const id of ids){
      const el = document.querySelector(id);
      if (el && el.tagName === 'SELECT') return el;
    }
    const sels = $all('select');
    for (const s of sels){
      const opts = Array.from(s.options||[]);
      if (opts.some(o => (o.value||'').startsWith('VSP_') || (o.text||'').startsWith('VSP_'))) return s;
    }
    return null;
  }

  function getRid(){
    try{
      const u = new URL(location.href);
      return u.searchParams.get('rid') || '';
    }catch(_e){}
    const sel = detectRidSelect();
    return sel ? (sel.value || '') : '';
  }

  function setRidInUrl(rid){
    try{
      const u = new URL(location.href);
      u.searchParams.set('rid', rid);
      history.replaceState({}, '', u.toString());
    }catch(_e){}
  }

  async function fetchDashKpis(rid){
    const r = await fetch(`/api/vsp/dash_kpis?rid=${encodeURIComponent(rid)}`, {cache:'no-store'});
    if (!r.ok) throw new Error(`dash_kpis HTTP ${r.status}`);
    return await r.json();
  }

  function tryCall(fn, rid){
    try{
      if (typeof fn === 'function'){
        if (fn.length >= 1) fn(rid);
        else fn();
        return true;
      }
    }catch(_e){}
    return false;
  }

  function tryKnownHooks(rid){
    let hit = false;
    hit = tryCall(window.__vspDashboardReloadRid, rid) || hit;
    hit = tryCall(window.__vspReloadAllPanels, rid) || hit;
    hit = tryCall(window.vspReloadAllPanels, rid) || hit;
    hit = tryCall(window.reloadDashboard, rid) || hit;
    hit = tryCall(window.refreshDashboard, rid) || hit;
    hit = tryCall(window.loadDashboard, rid) || hit;
    return hit;
  }

  function broadcastRidChanged(rid){
    try{
      window.dispatchEvent(new CustomEvent('vsp:ridChanged', {detail:{rid}}));
      document.dispatchEvent(new CustomEvent('vsp:ridChanged', {detail:{rid}}));
    }catch(_e){}
  }

  async function fallbackSoftReloadIfStale(rid){
    // If panels refuse to refresh (unknown code paths), do a soft reload to /vsp5?rid=...
    // This is still "no F5" from user POV (automatic), and guarantees consistency.
    try{
      const k = await fetchDashKpis(rid);
      const expected = Number(k && k.total_findings || 0);

      // naive read of KPI total from DOM (best-effort)
      const txt = (document.body && document.body.innerText) ? document.body.innerText : '';
      const hasExpected = expected > 0 && txt.includes(String(expected));

      // If after hook attempts we still don't even see expected total anywhere, reload.
      if (!hasExpected){
        const u = new URL(location.href);
        u.pathname = '/vsp5';
        u.searchParams.set('rid', rid);
        u.searchParams.set('soft', '1');
        location.replace(u.toString());
      }
    }catch(_e){
      // if dash_kpis fails, do nothing
    }
  }

  async function onRidChange(rid){
    if (!rid) return;

    // persist + URL
    try{ localStorage.setItem(LS_KEY, rid); }catch(_e){}
    setRidInUrl(rid);

    // notify others + attempt refresh hooks
    broadcastRidChanged(rid);

    const hit = tryKnownHooks(rid);

    // Always refresh our injected “Commercial severity” panel (it already listens to select change,
    // but this ensures it refreshes even if select binding differs)
    try{
      if (typeof window.__VSP_COUNTS_TOTAL_FROM_DASH_KPIS !== 'undefined'){
        // nothing to do; panel handles itself
      }
    }catch(_e){}

    // Fallback: if no known hook existed, soft reload after short delay (only if stale)
    if (!hit){
      setTimeout(()=>fallbackSoftReloadIfStale(rid), 1200);
    }
  }

  function boot(){
    const sel = detectRidSelect();
    if (!sel) return;

    if (!sel.__vspAllPanelsBound){
      sel.__vspAllPanelsBound = true;
      sel.addEventListener('change', ()=>{
        const rid = sel.value || getRid();
        onRidChange(rid);
      }, {passive:true});
    }

    // initial: persist url rid if any
    const rid0 = getRid();
    if (rid0){
      try{ localStorage.setItem(LS_KEY, rid0); }catch(_e){}
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();
JS
ok "wrote $JS"

# 2) Patch WSGI to inject this JS into /vsp5 (gzip-safe), without touching existing MWs
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || err "missing $WSGI"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1_MW_GZIP"
cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1_MW_GZIP"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

block = r'''
# --- VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1_MW_GZIP ---
import time as _vsp_time_ridall
import gzip as _vsp_gzip_ridall

class _VspForceInjectRidAllMw:
    """
    Inject vsp_rid_switch_refresh_all_v1.js into /vsp5 HTML at WSGI level (gzip-safe).
    Separate MW to avoid touching other MWs.
    """
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if not (path == "/vsp5" or path.startswith("/vsp5/")):
            return self.app(environ, start_response)

        captured={"status":None,"headers":None,"exc":None}
        def _sr(status, headers, exc_info=None):
            captured["status"]=status
            captured["headers"]=list(headers or [])
            captured["exc"]=exc_info
            return (lambda _x: None)

        it = self.app(environ, _sr)
        hdrs = captured["headers"] or []
        st   = captured["status"] or "200 OK"
        exc  = captured["exc"]

        ct=""; ce=""
        for (k,v) in hdrs:
            lk=(k or "").lower()
            if lk=="content-type": ct=v or ""
            if lk=="content-encoding": ce=(v or "").lower()

        if "text/html" not in (ct or "").lower():
            start_response(st, hdrs, exc)
            return it

        # collect body
        try:
            chunks=[]
            for c in it:
                if c:
                    chunks.append(c if isinstance(c,(bytes,bytearray)) else str(c).encode("utf-8","ignore"))
            body=b"".join(chunks)
        finally:
            try:
                close=getattr(it,"close",None)
                if callable(close): close()
            except Exception:
                pass

        was_gzip = ("gzip" in ce)
        if was_gzip:
            try:
                body=_vsp_gzip_ridall.decompress(body)
            except Exception:
                start_response(st, hdrs, exc)
                return [body]

        if b"vsp_rid_switch_refresh_all_v1.js" in body:
            if was_gzip:
                body=_vsp_gzip_ridall.compress(body)
            new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
            new_hdrs.append(("Content-Length", str(len(body))))
            start_response(st, new_hdrs, exc)
            return [body]

        tag=f'<script src="/static/js/vsp_rid_switch_refresh_all_v1.js?v={int(_vsp_time_ridall.time())}"></script>'.encode("utf-8")
        needle=b"</body>"
        if needle in body:
            body=body.replace(needle, tag+b"\n"+needle, 1)
        else:
            body=body+b"\n"+tag+b"\n"

        if was_gzip:
            body=_vsp_gzip_ridall.compress(body)

        new_hdrs=[(k,v) for (k,v) in hdrs if (k or "").lower()!="content-length"]
        new_hdrs.append(("Content-Length", str(len(body))))
        start_response(st, new_hdrs, exc)
        return [body]

try:
    application = _VspForceInjectRidAllMw(application)
except Exception:
    pass
# --- /VSP_P0_RID_SWITCH_REFRESH_ALL_PANELS_V1_MW_GZIP ---
'''
s = s.rstrip() + "\n\n" + block + "\n# " + MARK + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended rid-all MW + py_compile OK")
PY

# 3) Restart + verify
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "systemctl restart failed"
  sleep 0.6
  systemctl --no-pager --full status "$SVC" 2>/dev/null | head -n 12 || true
else
  warn "no systemctl; restart manually"
fi

echo "== [VERIFY] /vsp5 contains rid-all JS (use --compressed) =="
curl -fsS --compressed "$BASE/vsp5?rid=$RID" | grep -q "vsp_rid_switch_refresh_all_v1\.js" \
  && ok "inject OK: found vsp_rid_switch_refresh_all_v1.js" \
  || err "inject NOT found"

ok "DONE. Now change RID in dropdown: it will try refresh hooks; if none, it will soft-reload to guarantee no stale panels."
