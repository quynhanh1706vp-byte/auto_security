#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need node; need date; need sudo; need systemctl; need find; need sort; need grep

JS_DIR="static/js"
TPL_DIR="templates"
[ -d "$JS_DIR" ] || { echo "[ERR] missing $JS_DIR"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

# 1) All files in static/js that look like runs tab bundles (resolve/resolved + timestamp + even no .js suffix)
mapfile -t A < <(find "$JS_DIR" -maxdepth 1 -type f -name 'vsp_runs_tab_resolv*' -print | sort -u)

# 2) Also include any referenced asset names found in templates (in case file name is different)
mapfile -t B < <(
  [ -d "$TPL_DIR" ] && grep -RhoE 'vsp_runs_tab_resolv[^"'\'' ]+' "$TPL_DIR" 2>/dev/null | sort -u || true
)

FILES=()
for f in "${A[@]:-}"; do FILES+=("$f"); done

# try to resolve template refs into static/js paths
for ref in "${B[@]:-}"; do
  # ref may be "vsp_runs_tab_resolve__20251218_185216" (no extension)
  if [ -f "$JS_DIR/$ref" ]; then FILES+=("$JS_DIR/$ref"); fi
  if [ -f "$JS_DIR/$ref.js" ]; then FILES+=("$JS_DIR/$ref.js"); fi
done

# Always include the stable file if exists
if [ -f "$JS_DIR/vsp_runs_tab_resolved_v1.js" ]; then FILES+=("$JS_DIR/vsp_runs_tab_resolved_v1.js"); fi

# Dedup
mapfile -t FILES < <(printf '%s\n' "${FILES[@]}" | sort -u)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "[ERR] cannot locate runs-tab js to patch."
  echo "[HINT] run: ls -la static/js | grep vsp_runs_tab_resolv"
  exit 2
fi

echo "[INFO] files=${#FILES[@]} TS=$TS"
printf '%s\n' "${FILES[@]}" | sed 's/^/[FILE] /'

# Backup
for f in "${FILES[@]}"; do
  cp -f "$f" "$f.bak_throttle_${TS}"
done
echo "[OK] backups done (*.bak_throttle_${TS})"

PATCHER="/tmp/vsp_patch_poll_throttle_cache_${TS}.py"
cat > "$PATCHER" <<'PY'
from pathlib import Path
import sys

MARK="VSP_P1_POLL_THROTTLE_CACHE_V4"

INJECT = f"""// {MARK}
(function(){{
  if (window.__VSP_POLL_THROTTLE_CACHE) return;
  window.__VSP_POLL_THROTTLE_CACHE = true;

  const nativeFetch = window.fetch ? window.fetch.bind(window) : null;
  if (!nativeFetch) return;

  // throttle windows (ms)
  const MIN_RUNS = 12000;      // /api/vsp/runs
  const MIN_DASH = 15000;      // /api/vsp/dashboard*
  const st = {{
    last: Object.create(null),
    cache: Object.create(null),
    inflight: Object.create(null),
  }};

  function baseKey(u){{
    try {{
      const s = u.toString();
      // strip query (ts=...) so we cache per endpoint
      return s.split('?')[0];
    }} catch(e) {{
      return "";
    }}
  }}

  function isGuarded(u){{
    const s = (u||"").toString();
    if (!s.includes("/api/vsp/")) return false;
    // never touch downloads/exports/sha
    if (s.includes("/api/vsp/run_file")) return false;
    if (s.includes("/api/vsp/run_file2")) return false;
    if (s.includes("/api/vsp/export_")) return false;
    if (s.includes("/api/vsp/sha256")) return false;

    if (s.includes("/api/vsp/runs")) return true;
    if (s.includes("/api/vsp/dashboard")) return true; // includes dashboard_commercial_v2
    return false;
  }}

  function minInterval(key){{
    if (key.includes("/api/vsp/runs")) return MIN_RUNS;
    if (key.includes("/api/vsp/dashboard")) return MIN_DASH;
    return 0;
  }}

  async function guardedFetch(input, init){{
    const url = (typeof input === "string") ? input : (input && input.url) ? input.url : "";
    if (!url || !isGuarded(url)) {{
      return nativeFetch(input, init);
    }}
    const k = baseKey(url);
    const now = Date.now();
    const min = minInterval(k);
    const last = st.last[k] || 0;

    // If too soon and we have cache => serve cached JSON, NO network call => NO devtools spam
    if ((now - last) < min && st.cache[k]) {{
      return new Response(st.cache[k], {{
        status: 200,
        headers: {{
          "Content-Type": "application/json",
          "X-VSP-CACHED": "1"
        }}
      }});
    }}

    // If in-flight => also serve cache if possible
    if (st.inflight[k]) {{
      if (st.cache[k]) {{
        return new Response(st.cache[k], {{
          status: 200,
          headers: {{
            "Content-Type": "application/json",
            "X-VSP-CACHED": "1"
          }}
        }});
      }}
      return new Response(JSON.stringify({{ok:false, who:"VSP_POLL", error:"INFLIGHT"}}), {{
        status: 503, headers: {{"Content-Type":"application/json"}}
      }});
    }}

    st.inflight[k] = true;
    try {{
      const r = await nativeFetch(input, Object.assign({{}}, init||{{}}, {{ cache:"no-store" }}));
      // cache only OK JSON/text responses
      if (r && r.ok) {{
        try {{
          const txt = await r.clone().text();
          if (txt && txt.length < 5_000_000) {{
            st.cache[k] = txt;
            st.last[k] = now;
            return new Response(txt, {{
              status: 200,
              headers: {{
                "Content-Type": "application/json"
              }}
            }});
          }}
        }} catch(e) {{}}
      }}
      st.last[k] = now;
      return r;
    }} catch(e) {{
      // if fetch fails but cache exists, serve cache
      if (st.cache[k]) {{
        return new Response(st.cache[k], {{
          status: 200,
          headers: {{
            "Content-Type": "application/json",
            "X-VSP-CACHED": "1"
          }}
        }});
      }}
      throw e;
    }} finally {{
      st.inflight[k] = false;
    }}
  }}

  window.fetch = guardedFetch;
}})();
"""

def patch_one(fp: Path):
    s = fp.read_text(encoding="utf-8", errors="replace")
    if MARK in s:
        return "already"
    fp.write_text(INJECT + "\n" + s, encoding="utf-8")
    return "patched"

for f in sys.argv[1:]:
    fp = Path(f)
    print(fp.name, patch_one(fp))
PY

python3 "$PATCHER" "${FILES[@]}"

# syntax check only files with .js extension (node --check needs .js)
for f in "${FILES[@]}"; do
  case "$f" in
    *.js) node --check "$f" >/dev/null ;;
  esac
done
echo "[OK] node --check OK"

sudo systemctl restart vsp-ui-8910.service
sleep 1
echo "[OK] restarted"
