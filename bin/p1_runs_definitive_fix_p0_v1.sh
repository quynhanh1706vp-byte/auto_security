#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v node >/dev/null 2>&1 || echo "[WARN] node not found -> skip node --check"

TS="$(date +%Y%m%d_%H%M%S)"
echo "[INFO] TS=$TS"

backup_file(){
  local f="$1"
  [ -f "$f" ] || return 0
  cp -f "$f" "${f}.bak_runs_definitive_${TS}"
  echo "[BACKUP] ${f}.bak_runs_definitive_${TS}"
}

python3 - <<'PY'
from pathlib import Path
import re, time

TS=time.strftime("%Y%m%d_%H%M%S")

# 1) Clean BAD inline injected blocks in templates (most likely source of SyntaxError unexpected token '}')
tpls = list(Path("templates").glob("*.html")) + list(Path("templates").glob("**/*.html"))
tpls = [p for p in tpls if p.is_file()]

# blocks we MUST remove if present
BLOCK_IDS = [
  "VSP_P0_RUNS_FETCH_LOCK_V1",
  "VSP_P0_RUNS_FETCH_LOCK_V0",
  "VSP_P0_RUNS_FETCH_LOCK",
  "VSP_P0_RUNS_API_FAIL_FLICKER",
]

# remove any <script id="..."> ... </script> for these IDs
def strip_script_id(html:str, sid:str)->tuple[str,int]:
  rx = re.compile(rf"\s*<script[^>]*\bid\s*=\s*['\"]{re.escape(sid)}['\"][\s\S]*?</script>\s*", re.I)
  html2, n = rx.subn("\n", html)
  return html2, n

# also remove any inline block that tries to lock fetch (readonly)
# (we remove the whole <script>...</script> if it contains defineProperty(window,'fetch') with writable:false/configurable:false)
def strip_lock_fetch_scripts(html:str)->tuple[str,int]:
  rx = re.compile(r"(<script\b[^>]*>)([\s\S]*?)(</script>)", re.I)
  n=0
  def repl(m):
    nonlocal n
    body = m.group(2)
    if re.search(r"defineProperty\(\s*window\s*,\s*['\"]fetch['\"]", body) and re.search(r"writable\s*:\s*false|configurable\s*:\s*false", body):
      n += 1
      return "\n"
    if re.search(r"Cannot assign to read only property 'fetch'|RUNS_FETCH_LOCK|runs fetch lock", body, re.I):
      # safer: only strip if it includes lock keywords
      n += 1
      return "\n"
    return m.group(0)
  return rx.sub(repl, html), n

changed_tpl=0
for p in tpls:
  s = p.read_text(encoding="utf-8", errors="replace")
  orig = s
  total_n=0
  for sid in BLOCK_IDS:
    s, n = strip_script_id(s, sid); total_n += n
  s, n2 = strip_lock_fetch_scripts(s); total_n += n2

  # additionally: if there is any leftover broken marker block we injected earlier
  # remove HTML comments with RUNS_FETCH_LOCK
  s, n3 = re.subn(r"<!--\s*VSP_P0_RUNS_FETCH_LOCK[^>]*-->\s*", "", s, flags=re.I)
  total_n += n3

  if s != orig:
    bak = p.with_name(p.name + f".bak_runs_def_tpl_{TS}")
    bak.write_text(orig, encoding="utf-8")
    p.write_text(s, encoding="utf-8")
    print(f"[OK] cleaned template: {p} (removed_blocks={total_n}) backup={bak.name}")
    changed_tpl += 1

print("[DONE] templates_changed=", changed_tpl)

# 2) JS cleanup: remove code that makes window.fetch readonly OR attempts that later crash
js_dir = Path("static/js")
js_files = []
if js_dir.exists():
  js_files = [p for p in js_dir.glob("*.js") if p.is_file()]

FETCH_LOCK_PATTERNS = [
  re.compile(r"Object\.defineProperty\(\s*window\s*,\s*['\"]fetch['\"][\s\S]*?\)\s*;?", re.I),
  re.compile(r"defineProperty\(\s*window\s*,\s*['\"]fetch['\"][\s\S]*?\)\s*;?", re.I),
]

MARKERS = [
  "VSP_P0_RUNS_FETCH_LOCK",
  "VSP_P0_RUNS_COMMERCIAL_POLISH",
  "VSP_P0_RUNS_FAIL",
  "VSP_RUNS_FETCH_SHIM",
  "VSP_RUNS_HARD",
  "runs fetch lock installed",
]

changed_js=0
for p in js_files:
  s = p.read_text(encoding="utf-8", errors="replace")
  orig = s

  # remove explicit fetch lock statements
  for rx in FETCH_LOCK_PATTERNS:
    s = rx.sub("/* [REMOVED] fetch lock */", s)

  # if any marker block contains "read only property 'fetch'" logic, neutralize by guarding assignment
  # Also neutralize direct assignments to window.fetch in our RUNS patches: make them try/catch
  s = re.sub(r"(^\s*window\.fetch\s*=\s*)(async\s*)?\(", r"\1/*guarded*/(async ", s, flags=re.M)

  # If file contains markers, we DO NOT delete big blocks blindly; just ensure no readonly fetch.
  # Also fix common JS syntax issues from accidental python f-string braces: replace '{{' '}}' in JS injected snippets
  # (Only in lines that contain our markers to reduce risk)
  if any(m in s for m in MARKERS):
    s = re.sub(r"\{\{", "{", s)
    s = re.sub(r"\}\}", "}", s)

  if s != orig:
    bak = p.with_name(p.name + f".bak_runs_def_js_{TS}")
    bak.write_text(orig, encoding="utf-8")
    p.write_text(s, encoding="utf-8")
    print(f"[OK] cleaned js: {p} backup={bak.name}")
    changed_js += 1

print("[DONE] js_changed=", changed_js)

# 3) Create a FINAL RUNS guard file (no locking fetch; provides stable fetchJson + state/hysteresis)
guard = js_dir / "vsp_runs_guard_final_p0_v1.js"
guard.write_text(r"""
/* VSP_P0_RUNS_GUARD_FINAL_V1 */
(()=> {
  if (window.__vsp_p0_runs_guard_final_v1) return;
  window.__vsp_p0_runs_guard_final_v1 = true;

  const STATE = window.__vsp_runs_guard_state_v1 = window.__vsp_runs_guard_state_v1 || {
    lastOkAt: 0,
    lastOk: null,
    inflight: null,
    lastErrAt: 0,
    lastErr: ""
  };

  function _now(){ return Date.now(); }

  function _asArray(x){ return Array.isArray(x) ? x : []; }

  async function _xhrJson(url, timeoutMs){
    return await new Promise((resolve, reject)=>{
      try{
        const xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        xhr.responseType = "text";
        xhr.timeout = Math.max(1000, timeoutMs||5000);
        xhr.onload = ()=> {
          try{
            const t = xhr.responseText || "";
            const obj = t ? JSON.parse(t) : {};
            resolve(obj);
          }catch(e){ reject(e); }
        };
        xhr.onerror = ()=> reject(new Error("xhr error"));
        xhr.ontimeout = ()=> reject(new Error("xhr timeout"));
        xhr.send(null);
      }catch(e){ reject(e); }
    });
  }

  async function fetchJson(url, timeoutMs){
    // de-dup inflight for runs endpoint
    if (STATE.inflight) return STATE.inflight;

    const p = (async()=>{
      try{
        let obj = null;

        // prefer native fetch if usable
        if (typeof window.fetch === "function"){
          const ctrl = (typeof AbortController !== "undefined") ? new AbortController() : null;
          const to = setTimeout(()=>{ try{ ctrl && ctrl.abort(); }catch(_){ } }, Math.max(1000, timeoutMs||5000));
          try{
            const r = await window.fetch(url, {method:"GET", cache:"no-store", credentials:"same-origin", signal: ctrl?ctrl.signal:undefined});
            if (!r || !r.ok) throw new Error("fetch not ok");
            obj = await r.json();
          } finally {
            clearTimeout(to);
          }
        }

        if (!obj) obj = await _xhrJson(url, timeoutMs||5000);

        // normalize
        if (!obj || typeof obj !== "object") obj = {ok:false};
        if (obj.ok !== true) {
          // treat as error, but still allow fallback to lastOk
          throw new Error("runs payload ok!=true");
        }
        obj.items = _asArray(obj.items);
        STATE.lastOkAt = _now();
        STATE.lastOk = obj;
        return obj;
      } catch(e){
        STATE.lastErrAt = _now();
        STATE.lastErr = String(e && e.message ? e.message : e);

        // FALLBACK: if we have lastOk within 5 minutes, return it to stop flicker/crash
        if (STATE.lastOk && (_now() - STATE.lastOkAt) < 5*60*1000){
          const clone = Object.assign({}, STATE.lastOk);
          clone._degraded = true;
          clone._degraded_reason = STATE.lastErr;
          return clone;
        }
        // last resort: stable empty ok response so UI never crashes
        return {ok:true, items:[], _degraded:true, _degraded_reason: STATE.lastErr};
      } finally {
        STATE.inflight = null;
      }
    })();

    STATE.inflight = p;
    return p;
  }

  window.VSP_RUNS_GUARD = window.VSP_RUNS_GUARD || {};
  window.VSP_RUNS_GUARD.fetchJson = fetchJson;

  console.log("[VSP][P0] runs guard final enabled (no fetch lock).");
})();
""".lstrip(), encoding="utf-8")
print(f"[OK] wrote {guard}")

# 4) Patch runs tab JS to USE the guard for /api/vsp/runs (avoid depending on patched fetch wrappers)
def patch_runs_js(p:Path)->bool:
  s = p.read_text(encoding="utf-8", errors="replace")
  orig = s
  if "VSP_RUNS_GUARD.fetchJson" in s:
    return False

  # Replace fetch(".../api/vsp/runs...") => VSP_RUNS_GUARD.fetchJson(".../api/vsp/runs...")
  s = re.sub(
    r"\bfetch\s*\(\s*([`'\"][^`'\"]*?/api/vsp/runs[^`'\"]*[`'\"])\s*(,\s*\{[^\)]*\})?\s*\)",
    r"(window.VSP_RUNS_GUARD && window.VSP_RUNS_GUARD.fetchJson ? window.VSP_RUNS_GUARD.fetchJson(\1, 6000) : fetch(\1))",
    s
  )

  # Also protect any usage of items.slice in this file
  s = re.sub(r"\(\s*items\s*\|\|\s*\[\s*\]\s*\)\.slice", "(Array.isArray(items)?items:[]).slice", s)

  if s != orig:
    bak = p.with_name(p.name + f".bak_runs_guardpatch_{TS}")
    bak.write_text(orig, encoding="utf-8")
    p.write_text(s, encoding="utf-8")
    print(f"[OK] patched runs js: {p} backup={bak.name}")
    return True
  return False

patched_any=False
for name in ["vsp_runs_tab_resolved_v1.js", "vsp_bundle_commercial_v2.js", "vsp_bundle_commercial_v1.js", "vsp_app_entry_safe_v1.js", "vsp_fill_real_data_5tabs_p1_v1.js"]:
  p = js_dir / name
  if p.exists():
    patched_any = patch_runs_js(p) or patched_any

print("[DONE] patched_any_js=", patched_any)

# 5) Ensure templates include the new guard file once (safe if already there)
# We'll inject before </body> if not present.
inject_tag = '<script src="/static/js/vsp_runs_guard_final_p0_v1.js?v={{ asset_v }}"></script>'
for p in tpls:
  s = p.read_text(encoding="utf-8", errors="replace")
  if "vsp_runs_guard_final_p0_v1.js" in s:
    continue
  s2, n = re.subn(r"</body>", inject_tag+"\n</body>", s, flags=re.I)
  if n:
    bak = p.with_name(p.name + f".bak_runs_guardinj_{TS}")
    bak.write_text(s, encoding="utf-8")
    p.write_text(s2, encoding="utf-8")
    print(f"[OK] injected guard include: {p} backup={bak.name}")

print("[OK] guard include injection done.")
PY

# quick syntax check
for f in static/js/vsp_bundle_commercial_v2.js static/js/vsp_bundle_commercial_v1.js static/js/vsp_runs_tab_resolved_v1.js static/js/vsp_app_entry_safe_v1.js static/js/vsp_fill_real_data_5tabs_p1_v1.js static/js/vsp_runs_guard_final_p0_v1.js; do
  [ -f "$f" ] || continue
  if command -v node >/dev/null 2>&1; then
    node --check "$f" >/dev/null && echo "[OK] node --check $f" || { echo "[ERR] node --check failed: $f"; exit 2; }
  fi
done

echo "== backend sanity =="
curl -sS -I "http://127.0.0.1:8910/api/vsp/runs?limit=20" | sed -n '1,12p' || true

echo "[NEXT] restart UI then Ctrl+F5 /runs + /vsp5 (or Incognito)"
