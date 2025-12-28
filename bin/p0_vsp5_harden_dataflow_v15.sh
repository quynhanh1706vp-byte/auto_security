#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need curl; need grep; need ss

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
SHIM="static/js/vsp_p0_fetch_shim_v1.js"
GS="static/js/vsp_dashboard_gate_story_v1.js"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_v15_${TS}"
echo "[BACKUP] ${WSGI}.bak_v15_${TS}"

mkdir -p "$(dirname "$SHIM")"

cat > "$SHIM" <<'JS'
/* VSP_P0_FETCH_SHIM_V1
 * - Alias /api/vsp/rid_latest -> /api/vsp/rid_latest_gate_root
 * - Rewrite /api/vsp/run_file -> /api/vsp/run_file_allow
 * - Normalize RID variants (VSP_CI_* <-> VSP_CI_RUN_*)
 * - Retry with gate_root_* when run_file_allow fails
 * - Abort requests that hang too long (prevents infinite LOADING)
 */
(()=> {
  if (window.__vsp_p0_fetch_shim_v1) return;
  window.__vsp_p0_fetch_shim_v1 = true;

  const RID_EP = "/api/vsp/rid_latest_gate_root";
  const RUNFILE_ALLOW = "/api/vsp/run_file_allow";

  const uniq = (arr)=> Array.from(new Set(arr.filter(Boolean)));

  const ridVariants = (rid) => {
    if (!rid) return [];
    let r = String(rid);
    const out = [r];

    // normalize common variants
    // VSP_CI_YYYYmmdd_HHMMSS  <->  VSP_CI_RUN_YYYYmmdd_HHMMSS
    if (r.startsWith("VSP_CI_") && !r.startsWith("VSP_CI_RUN_")) {
      out.push(r.replace(/^VSP_CI_/, "VSP_CI_RUN_"));
    }
    if (r.startsWith("VSP_CI_RUN_")) {
      out.push(r.replace(/^VSP_CI_RUN_/, "VSP_CI_"));
    }
    // sometimes "_RUN_" appears mid-string
    out.push(r.replace(/_RUN_/g, "_"));
    out.push(r.replace(/_/g, "_RUN_")); // last resort variant (won't hurt due to uniq)
    return uniq(out);
  };

  let _latestCache = { t: 0, p: null };
  async function getLatest(force=false){
    const now = Date.now();
    if (!force && _latestCache.p && (now - _latestCache.t) < 8000) return _latestCache.p;
    _latestCache.t = now;
    _latestCache.p = (async()=>{
      const r = await fetch(RID_EP, { cache: "no-store" });
      const j = await r.json().catch(()=> ({}));
      return j || {};
    })();
    return _latestCache.p;
  }

  function toURL(input){
    try{
      if (typeof input === "string") return new URL(input, location.origin);
      if (input && typeof input.url === "string") return new URL(input.url, location.origin); // Request
    }catch(_){}
    return null;
  }

  async function fetchWithTimeout(origFetch, url, init, ms){
    const ctrl = (typeof AbortController !== "undefined") ? new AbortController() : null;
    const t = ctrl ? setTimeout(()=>{ try{ ctrl.abort(); }catch(_){} }, ms) : null;
    const init2 = ctrl ? Object.assign({}, init || {}, { signal: ctrl.signal }) : (init || {});
    try{
      return await origFetch(url, init2);
    } finally {
      if (t) clearTimeout(t);
    }
  }

  function initNoCache(init){
    const h = new Headers((init && init.headers) || {});
    // ensure we don't get stuck by cached 404s
    h.set("Cache-Control","no-cache");
    return Object.assign({}, init || {}, { headers: h, cache: "no-store" });
  }

  const origFetch = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const u = toURL(input);
    if (!u) return origFetch(input, init);

    // alias rid_latest -> rid_latest_gate_root
    if (u.pathname === "/api/vsp/rid_latest") u.pathname = RID_EP;

    // rewrite run_file -> run_file_allow
    if (u.pathname === "/api/vsp/run_file") u.pathname = RUNFILE_ALLOW;

    // if run_file_allow but missing rid -> fill from latest
    if (u.pathname === RUNFILE_ALLOW) {
      const sp = u.searchParams;
      let rid = sp.get("rid");
      if (!rid || rid === "None" || rid === "null") {
        const latest = await getLatest(false).catch(()=> ({}));
        rid = latest.rid || latest.run_id || latest.gate_root || latest.gate_root_id || "";
        if (rid) sp.set("rid", rid);
      }
    }

    // retry logic only for run_file_allow
    if (u.pathname === RUNFILE_ALLOW) {
      const sp = u.searchParams;
      const path = sp.get("path") || "";
      const rid0 = sp.get("rid") || "";
      const latest = await getLatest(false).catch(()=> ({}));
      const gr0 = latest.gate_root || latest.gate_root_id || "";

      const candidates = uniq([
        ...ridVariants(rid0),
        ...ridVariants(gr0),
      ]);

      const baseInit = initNoCache(init);
      const timeoutMs = 8000;

      for (let i=0; i<Math.min(candidates.length, 6); i++){
        const rid = candidates[i];
        const uu = new URL(u.toString());
        uu.searchParams.set("rid", rid);

        const resp = await fetchWithTimeout(origFetch, uu.toString(), baseInit, timeoutMs).catch(()=> null);
        if (resp && resp.ok) return resp;

        // If server returns 200 but body isn't JSON, UI still breaks; let next try happen.
        if (resp && resp.ok) {
          const ct = (resp.headers.get("content-type") || "").toLowerCase();
          if (ct.includes("application/json")) return resp;
        }
      }

      // last attempt: original url
      return fetchWithTimeout(origFetch, u.toString(), baseInit, timeoutMs);
    }

    return fetchWithTimeout(origFetch, u.toString(), initNoCache(init), 8000);
  };

  // XHR alias too (some modules still use XMLHttpRequest)
  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url, ...rest){
    try{
      const u = new URL(String(url), location.origin);
      if (u.pathname === "/api/vsp/rid_latest") u.pathname = RID_EP;
      if (u.pathname === "/api/vsp/run_file") u.pathname = RUNFILE_ALLOW;
      return origOpen.call(this, method, u.toString(), ...rest);
    }catch(_){
      return origOpen.call(this, method, url, ...rest);
    }
  };

  console.log("[VSP] fetch shim active: VSP_P0_FETCH_SHIM_V1");
})();
JS

echo "[OK] wrote $SHIM"

# Patch GateStory dedupe guard (safe even if already patched)
if [ -f "$GS" ]; then
  cp -f "$GS" "${GS}.bak_v15_${TS}"
  python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_dashboard_gate_story_v1.js")
s=p.read_text(encoding="utf-8", errors="replace")
if "VSP_P0_GATE_STORY_DEDUPE_GUARD_V15" in s:
    print("[OK] GateStory dedupe already present")
    raise SystemExit(0)

guard = r"""
/* VSP_P0_GATE_STORY_DEDUPE_GUARD_V15 */
(()=>{ try{
  if (window.__vsp_gate_story_v15_loaded) return;
  window.__vsp_gate_story_v15_loaded = true;
} catch(_){}})();
"""
# insert at top (after possible shebang/comments)
s2 = guard + "\n" + s
p.write_text(s2, encoding="utf-8")
print("[OK] injected GateStory dedupe guard v15")
PY
fi

# Patch WSGI bundle_tag for /vsp5 injection: make canonical order + include shim FIRST
python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
marker = "VSP_P0_VSP5_BUNDLETAG_CANON_V15"
if marker in s:
    print("[OK] WSGI already has", marker)
    raise SystemExit(0)

lines = s.splitlines(True)

# choose an anchor region near VSP5 bundle inject middleware (best-effort)
anchors = []
for i,l in enumerate(lines):
    ll = l.lower()
    if "vsp5" in ll and ("bundle" in ll or "inject" in ll or "middleware" in ll or "html" in ll):
        anchors.append(i)
if not anchors:
    # fallback: just search for bundle_tag occurrences
    anchors = [0]

def find_bundle_tag(start):
    for j in range(start, min(start+5000, len(lines))):
        if re.match(r'^\s*bundle_tag\s*=', lines[j]):
            return j
    return None

start = None
for a in anchors:
    start = find_bundle_tag(a)
    if start is not None:
        break
if start is None:
    # ultimate fallback: global scan
    start = find_bundle_tag(0)

if start is None:
    raise SystemExit("[ERR] cannot find bundle_tag assignment in WSGI")

indent = re.match(r'^(\s*)', lines[start]).group(1)

# determine end of current assignment (handles single-line, triple-quote, or parenthesis block)
end = start
first = lines[start]
if "'''" in first or '"""' in first:
    q = "'''" if "'''" in first else '"""'
    k = start + 1
    while k < len(lines):
        end = k
        if q in lines[k]:
            break
        k += 1
elif "(" in first and not first.rstrip().endswith(")"):
    depth = first.count("(") - first.count(")")
    k = start + 1
    while k < len(lines) and depth > 0:
        depth += lines[k].count("(") - lines[k].count(")")
        end = k
        k += 1
else:
    end = start

canon = (
    f"{indent}# {marker}\n"
    f"{indent}bundle_tag = (\n"
    f"{indent}    f'<script src=\"/static/js/vsp_p0_fetch_shim_v1.js?v={{v}}\"></script>'\n"
    f"{indent}    f'<script src=\"/static/js/vsp_bundle_commercial_v2.js?v={{v}}\"></script>'\n"
    f"{indent}    f'<script src=\"/static/js/vsp_dashboard_gate_story_v1.js?v={{v}}\"></script>'\n"
    f"{indent}    f'<script src=\"/static/js/vsp_dashboard_containers_fix_v1.js?v={{v}}\"></script>'\n"
    f"{indent}    f'<script src=\"/static/js/vsp_dashboard_luxe_v1.js?v={{v}}\"></script>'\n"
    f"{indent})\n"
)

new_lines = lines[:start] + [canon] + lines[end+1:]
p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] patched bundle_tag at lines {start+1}-{end+1} with {marker}")
PY

echo "== py_compile WSGI =="
python3 -m py_compile "$WSGI" && echo "[OK] py_compile OK"

echo "== restart service =="
systemctl restart "$SVC" || { echo "[ERR] systemctl restart failed"; systemctl status "$SVC" --no-pager || true; exit 2; }

echo "== wait /vsp5 =="
for i in $(seq 1 80); do
  curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null && break
  sleep 0.25
done

echo "== smoke scripts list (should include shim + bundle once each ideally) =="
curl -fsS "$BASE/vsp5" | egrep -n "vsp_p0_fetch_shim_v1|vsp_bundle_commercial_v2|vsp_dashboard_gate_story_v1|vsp_dashboard_containers_fix_v1|vsp_dashboard_luxe_v1" | head -n 80 || true

echo "== smoke rid_latest_gate_root =="
curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | head -c 240; echo

echo "== smoke run_file_allow with rid (from rid_latest_gate_root) =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest_gate_root" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -sS -i "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" | head -n 18

echo
echo "[DONE] Now do hard reload: Ctrl+Shift+R on $BASE/vsp5"
echo "[TIP ] Open DevTools console and confirm: '[VSP] fetch shim active: VSP_P0_FETCH_SHIM_V1'"
