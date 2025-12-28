#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }

JS="static/js/vsp_fetch_guard_rid_v1.js"
mkdir -p static/js

cp -f "$JS" "${JS}.bak_${TS}" 2>/dev/null || true

cat > "$JS" <<'JS'
/* VSP_FETCH_GUARD_RID_V1: force rid + timeout for /api/vsp/* */
(function(){
  if (window.__VSP_FETCH_GUARD_RID_V1__) return;
  window.__VSP_FETCH_GUARD_RID_V1__ = { ok:true, ts: Date.now() };

  function getRidFromUrl(){
    try{
      var u = new URL(window.location.href);
      return (u.searchParams.get("rid") || "").trim();
    }catch(_){ return ""; }
  }

  var RID = getRidFromUrl();
  window.__VSP_ACTIVE_RID__ = RID;

  var _fetch = window.fetch;
  if (typeof _fetch !== "function") return;

  function withRid(url){
    try{
      if (!RID) return url;
      // Only patch /api/vsp/*
      if (typeof url !== "string") return url;
      if (!url.startsWith("/api/vsp/")) return url;
      // endpoints that should NOT be forced
      if (url.startsWith("/api/vsp/rid_latest")) return url;
      // already has rid
      if (url.indexOf("rid=") !== -1) return url;

      var u = new URL(url, window.location.origin);
      u.searchParams.set("rid", RID);
      return u.pathname + (u.search ? u.search : "");
    }catch(_){
      return url;
    }
  }

  function fetchWithTimeout(input, init){
    var timeoutMs = 10000;
    var controller = ("AbortController" in window) ? new AbortController() : null;
    var t = null;

    if (controller){
      init = init || {};
      // If caller already has signal, respect it
      if (!init.signal) init.signal = controller.signal;
      t = setTimeout(function(){ try{ controller.abort(); }catch(_){} }, timeoutMs);
    }

    var patchedInput = input;
    if (typeof input === "string"){
      patchedInput = withRid(input);
    }else if (input && typeof input.url === "string"){
      // Request object: keep it (do not reconstruct), but we can’t safely mutate -> skip
    }

    return _fetch(patchedInput, init).finally(function(){
      if (t) clearTimeout(t);
    });
  }

  window.fetch = fetchWithTimeout;
})();
JS

ok "write: $JS"

# Inject into templates that have CIO shell (idempotent)
python3 - <<'PY'
from pathlib import Path
import re

tpl_dir = Path("templates")
if not tpl_dir.exists():
    print("[WARN] templates/ not found; skip injection")
    raise SystemExit(0)

tag = 'vsp_fetch_guard_rid_v1.js'
patched = 0

for p in tpl_dir.rglob("*.html"):
    s = p.read_text(encoding="utf-8", errors="replace")
    if "vsp_cio_shell_apply_v1.js" not in s:
        continue
    if tag in s:
        continue
    orig = s

    # Prefer insert right after CIO apply script
    m = re.search(r'(<script[^>]+vsp_cio_shell_apply_v1\.js[^>]*></script>)', s)
    if m:
        ins = m.group(1) + f'\n  <script src="/static/js/{tag}?v=rid_guard"></script>'
        s = s.replace(m.group(1), ins, 1)
    else:
        s = re.sub(r'(</body>)', f'  <script src="/static/js/{tag}?v=rid_guard"></script>\n\\1', s, count=1)

    if s != orig:
        b = p.with_suffix(p.suffix + ".bak_ridguard")
        if not b.exists():
            b.write_text(orig, encoding="utf-8")
        p.write_text(s, encoding="utf-8")
        patched += 1

print(f"[OK] templates_patched={patched}")
PY

# Restart service
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && ok "service active: $SVC" || warn "service not active; check systemctl status $SVC"
else
  warn "no systemctl; skip restart"
fi

ok "DONE. Now Ctrl+F5 /vsp5?rid=... and check data loads."
