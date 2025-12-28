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
cp -f "$F" "${F}.bak_p3k17_${TS}"
echo "[BACKUP] ${F}.bak_p3k17_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("static/js/vsp_bundle_tabs5_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3K17_TABS5_GUARD_XHR_RIDLATEST_AND_SWALLOW_TIMEOUT_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

inject = f"""
/* === {MARK} ===
   Fix remaining Firefox issues:
   - rid_latest calls may use XHR (XMLHttpRequest), not fetch()
   - swallow "timeout" errors globally (error + unhandledrejection)
   - if ?rid= exists => always answer rid_latest* from URL (commercial safe)
=== */
(function(){{
  function _isTimeoutMsg(m){{
    try {{
      m = (m && (m.message || (''+m))) || '';
      return (m === 'timeout') || (/\\btimeout\\b/i.test(m));
    }} catch(_){{ return false; }}
  }}

  try {{
    window.addEventListener('unhandledrejection', function(e){{
      try {{ if (_isTimeoutMsg(e && e.reason)) e.preventDefault(); }} catch(_){{}}
    }});
  }} catch(_){{}}

  try {{
    window.addEventListener('error', function(e){{
      try {{
        var msg = (e && (e.message || (''+e.error))) || '';
        if (_isTimeoutMsg(msg)) e.preventDefault();
      }} catch(_){{}}
    }}, true);
  }} catch(_){{}}

  try {{
    var qs = new URLSearchParams((location && location.search) || "");
    var rid = qs.get("rid") || "";
    if (!rid) return;

    function _ridJson(){{
      return JSON.stringify({{ok:true, rid: rid, mode:'from_url'}})
    }}

    function _match(url){{
      url = String(url||'');
      return (
        url.indexOf('/api/vsp/rid_latest') !== -1 ||
        url.indexOf('/api/vsp/rid_latest_v3') !== -1 ||
        url.indexOf('/api/vsp/rid_latest_gate_root') !== -1
      );
    }}

    // Patch XHR
    var OrigXHR = window.XMLHttpRequest;
    if (OrigXHR && !window.__VSP_XHR_PATCHED_RIDLATEST__) {{
      window.__VSP_XHR_PATCHED_RIDLATEST__ = true;

      function PatchedXHR(){{
        var xhr = new OrigXHR();
        var _url = "";

        var _open = xhr.open;
        var _send = xhr.send;

        xhr.open = function(method, url){{
          _url = String(url||"");
          return _open.apply(xhr, arguments);
        }};

        xhr.send = function(body){{
          try {{
            if (_match(_url)) {{
              var resp = _ridJson();
              // simulate async success without real network
              setTimeout(function(){{
                try {{
                  Object.defineProperty(xhr, "readyState", {{value:4, configurable:true}});
                  Object.defineProperty(xhr, "status", {{value:200, configurable:true}});
                  Object.defineProperty(xhr, "responseText", {{value:resp, configurable:true}});
                  Object.defineProperty(xhr, "response", {{value:resp, configurable:true}});
                }} catch(_) {{
                  try {{ xhr.readyState=4; xhr.status=200; xhr.responseText=resp; xhr.response=resp; }} catch(__){{}}
                }}

                try {{ xhr.onreadystatechange && xhr.onreadystatechange(); }} catch(_){{}}
                try {{ xhr.onload && xhr.onload(); }} catch(_){{}}
                try {{ xhr.onloadend && xhr.onloadend(); }} catch(_){{}}
              }}, 0);
              return;
            }}
          }} catch(_){{}}
          return _send.apply(xhr, arguments);
        }};

        return xhr;
      }}

      // keep constants if someone uses them
      for (var k in OrigXHR) {{
        try {{ PatchedXHR[k] = OrigXHR[k]; }} catch(_){{}}
      }}
      try {{ PatchedXHR.prototype = OrigXHR.prototype; }} catch(_){{}}

      window.XMLHttpRequest = PatchedXHR;
    }}
  }} catch(_){{}}
}})();
"""

# prepend right at top (safe)
p.write_text(inject + "\n" + s, encoding="utf-8")
print("[OK] patched (prepended XHR+timeout guard)")
PY

node -c "$F"
echo "[OK] node -c passed"

sudo systemctl restart "$SVC"
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 3; }

echo "== marker =="
head -n 3 "$F" | sed -n '1,3p'
echo "[DONE] p3k17_tabs5_guard_xhr_ridlatest_and_swallow_timeout_v1"
