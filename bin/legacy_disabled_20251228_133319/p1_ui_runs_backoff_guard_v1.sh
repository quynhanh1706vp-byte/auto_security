#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

JS="static/js/vsp_runs_tab_resolved_v1.js"
[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_backoff_${TS}"
echo "[BACKUP] ${JS}.bak_backoff_${TS}"

python3 - <<'PY'
from pathlib import Path

p=Path("static/js/vsp_runs_tab_resolved_v1.js")
lines=p.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK="VSP_P1_UI_RUNS_BACKOFF_GUARD_V1"
if any(MARK in ln for ln in lines):
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

inject = f"""// {MARK}
(function(){{
  if (window.__VSP_FETCH_RUNS) return;
  let inflight = false;
  let backoffMs = 2000;          // 2s -> 4 -> 8 ... max 60s
  let nextTryAt = 0;
  let lastErrAt = 0;

  function now(){{ return Date.now(); }}
  function okResponse(obj, status){{
    try {{
      return new Response(JSON.stringify(obj), {{
        status: status || 200,
        headers: {{ "Content-Type":"application/json" }}
      }});
    }} catch(e) {{
      // very old browsers fallback
      return {{
        ok: false,
        status: status || 503,
        json: async()=>obj
      }};
    }}
  }}

  window.__VSP_FETCH_RUNS = async function(input, init){{
    const t = now();
    if (t < nextTryAt) {{
      // backoff window: return soft 503 JSON (no throw)
      return okResponse({{ok:false, who:"VSP_RUNS_BACKOFF", items:[], items_len:0, error:"BACKOFF"}}, 503);
    }}
    if (inflight) {{
      // avoid concurrent spam
      return okResponse({{ok:false, who:"VSP_RUNS_BACKOFF", items:[], items_len:0, error:"INFLIGHT"}}, 503);
    }}

    inflight = true;
    const ctrl = new AbortController();
    const timeoutMs = 8000;
    const timer = setTimeout(()=>ctrl.abort(), timeoutMs);

    try {{
      const _init = Object.assign({{}}, init||{{}});
      _init.signal = ctrl.signal;
      _init.cache = "no-store";
      const r = await fetch(input, _init);
      // If server is up but returns non-2xx, still reset backoff (it responded)
      backoffMs = 2000;
      nextTryAt = 0;
      return r;
    }} catch(e) {{
      // service restarting -> connection reset/failed fetch
      const t2 = now();
      if (t2 - lastErrAt > 3000) {{
        // log at most once per 3s
        console.warn("[VSP][runs] fetch failed; backoff", backoffMs, "ms");
        lastErrAt = t2;
      }}
      nextTryAt = t2 + backoffMs;
      backoffMs = Math.min(backoffMs * 2, 60000);
      return okResponse({{ok:false, who:"VSP_RUNS_BACKOFF", items:[], items_len:0, error:"FETCH_FAILED"}}, 503);
    }} finally {{
      clearTimeout(timer);
      inflight = false;
    }}
  }};
}})();
"""

# insert wrapper at top of file after any "use strict" line if present
out=[]
inserted=False
for i,ln in enumerate(lines):
    out.append(ln)
    if not inserted:
        if '"use strict"' in ln or "'use strict'" in ln:
            out.append("\n"+inject+"\n")
            inserted=True
if not inserted:
    out = [inject+"\n"] + out

# replace per-line: fetch(.../api/vsp/runs...) -> window.__VSP_FETCH_RUNS(...)
patched=0
for i,ln in enumerate(out):
    if "/api/vsp/runs" in ln and "fetch(" in ln and "__VSP_FETCH_RUNS" not in ln:
        out[i]=ln.replace("fetch(", "window.__VSP_FETCH_RUNS(", 1)
        patched += 1

p.write_text("".join(out), encoding="utf-8")
print(f"[OK] injected wrapper + patched fetch lines: {patched}")
PY

node --check static/js/vsp_runs_tab_resolved_v1.js
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
