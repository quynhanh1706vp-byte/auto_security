#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="static/js/vsp_bundle_tabs5_v1.js"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need node; need date
command -v systemctl >/dev/null 2>&1 || true

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

cp -f "$F" "${F}.bak_p3k16_${TS}"
echo "[BACKUP] ${F}.bak_p3k16_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3K16_TABS5_GUARD_RIDLATEST_AND_SWALLOW_TIMEOUT_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

guard = f"""/* === {MARK} ===
   Goal: commercial-safe dashboard
   - prefer rid from URL (?rid=)
   - short-circuit /api/vsp/rid_latest* calls using rid from URL (avoid timeout/abort)
   - swallow unhandledrejection 'timeout' to avoid console spam
=== */
(function(){{
  try {{
    window.addEventListener('unhandledrejection', function(e){{
      try {{
        var r = e && e.reason;
        var msg = (r && (r.message || (''+r))) || '';
        if (msg === 'timeout' || /timeout/i.test(msg)) {{ e.preventDefault(); return; }}
      }} catch(_){{}}
    }});
  }} catch(_){{}}

  try {{
    var qs = new URLSearchParams((location && location.search) || "");
    var rid = qs.get("rid") || "";
    if (rid) {{
      // publish common globals (best-effort)
      window.__VSP_RID__ = rid;
      window.__VSP_RID_CURRENT__ = rid;
      window.__VSP_RID_LATEST__ = rid;
      window.__VSP_SKIP_RID_LATEST__ = true;

      // fetch short-circuit: rid_latest, rid_latest_v3, rid_latest_gate_root
      var _fetch = window.fetch ? window.fetch.bind(window) : null;
      if (_fetch && !window.__VSP_FETCH_PATCHED_RIDLATEST__) {{
        window.__VSP_FETCH_PATCHED_RIDLATEST__ = true;
        window.fetch = function(input, init){{
          try {{
            var url = (typeof input === 'string') ? input : (input && input.url) ? input.url : '';
            if (url && url.indexOf('/api/vsp/rid_latest') !== -1) {{
              var body = JSON.stringify({{ok:true, rid: rid, mode:'from_url'}});
              return Promise.resolve(new Response(body, {{
                status: 200,
                headers: {{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}}
              }}));
            }}
            if (url && url.indexOf('/api/vsp/rid_latest_v3') !== -1) {{
              var body2 = JSON.stringify({{ok:true, rid: rid, mode:'from_url'}});
              return Promise.resolve(new Response(body2, {{
                status: 200,
                headers: {{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}}
              }}));
            }}
            if (url && url.indexOf('/api/vsp/rid_latest_gate_root') !== -1) {{
              var body3 = JSON.stringify({{ok:true, rid: rid, mode:'from_url'}});
              return Promise.resolve(new Response(body3, {{
                status: 200,
                headers: {{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}}
              }}));
            }}
          }} catch(_){{}}
          return _fetch(input, init);
        }};
      }}
    }}
  }} catch(e) {{
    // do nothing
  }}
}})();

"""

# prepend guard at top
p.write_text(guard + "\n" + s, encoding="utf-8")
print("[OK] patched (prepended guard)")
PY

echo "== node -c =="
node -c "$F"
echo "[OK] node -c passed"

echo "== restart =="
sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== marker =="
head -n 3 "$F" | sed -n '1,3p'
echo "[DONE] p3k16_tabs5_guard_ridlatest_and_swallow_timeout_v1"
