#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need sed

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
JS_LUXE="static/js/vsp_dashboard_luxe_v1.js"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$JS_LUXE" ] || { echo "[ERR] missing $JS_LUXE"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

cp -f "$WSGI" "${WSGI}.bak_relid_${TS}"
echo "[BACKUP] ${WSGI}.bak_relid_${TS}"

cp -f "$JS_LUXE" "${JS_LUXE}.bak_autorf_${TS}"
echo "[BACKUP] ${JS_LUXE}.bak_autorf_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, os, json, time

wsgi = Path("wsgi_vsp_ui_gateway.py")
s = wsgi.read_text(encoding="utf-8", errors="replace")

marker = "VSP_P0_RELEASE_IDENTITY_AND_ASSET_V1"
if marker not in s:
    block = r'''
# ===================== VSP_P0_RELEASE_IDENTITY_AND_ASSET_V1 =====================
# - Provide stable asset_v from release_latest.json (or static mtime fallback)
# - Add response headers: X-VSP-RELEASE-TS/SHA/PKG
# - Ensure HTML is no-store to avoid stale UI after deploy
import os, json, time
from pathlib import Path

def _vsp_find_release_latest_json():
    # prefer explicit env, else try common locations
    cands = []
    envp = os.environ.get("VSP_RELEASE_LATEST_JSON","").strip()
    if envp:
        cands.append(Path(envp))
    cands += [
        Path("/home/test/Data/SECURITY_BUNDLE/out/release_latest.json"),
        Path("/home/test/Data/SECURITY_BUNDLE/ui/out/release_latest.json"),
        Path("out/release_latest.json"),
        Path("../out/release_latest.json"),
    ]
    for p in cands:
        try:
            if p.is_file() and p.stat().st_size > 0:
                return p
        except Exception:
            pass
    return None

def _vsp_load_release_meta():
    meta = {"ts": "", "sha": "", "pkg": "", "ok": False}
    p = _vsp_find_release_latest_json()
    if not p:
        return meta
    try:
        j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        meta["ts"]  = str(j.get("release_ts","") or j.get("ts","") or "")
        meta["sha"] = str(j.get("release_sha","") or j.get("sha","") or "")
        meta["pkg"] = str(j.get("release_pkg","") or j.get("pkg","") or "")
        meta["ok"]  = True
        return meta
    except Exception:
        return meta

def _vsp_asset_v():
    # stable per-release if possible; fallback to bundle mtime; fallback to day
    m = _vsp_load_release_meta()
    if m.get("ts"):
        # keep only digits so it can be used in ?v=
        digits = "".join([c for c in m["ts"] if c.isdigit()])
        if digits:
            return digits
    try:
        p = Path("static/js/vsp_bundle_commercial_v2.js")
        if p.is_file():
            return str(int(p.stat().st_mtime))
    except Exception:
        pass
    return str(int(time.time()//86400))  # daily

def _vsp_release_headers(resp):
    try:
        m = _vsp_load_release_meta()
        if m.get("ts"):  resp.headers["X-VSP-RELEASE-TS"]  = m["ts"]
        if m.get("sha"): resp.headers["X-VSP-RELEASE-SHA"] = m["sha"]
        if m.get("pkg"): resp.headers["X-VSP-RELEASE-PKG"] = m["pkg"]
    except Exception:
        pass
    return resp

# Try to register context_processor & after_request if Flask app object is present
try:
    _APP_CANDS = []
    for _nm in ("app","application"):
        if _nm in globals():
            _APP_CANDS.append(globals()[_nm])
    for _a in _APP_CANDS:
        try:
            @_a.context_processor
            def _vsp_ctx():
                return {"asset_v": _vsp_asset_v(), "release_meta": _vsp_load_release_meta()}
        except Exception:
            pass
        try:
            @_a.after_request
            def _vsp_after(resp):
                resp = _vsp_release_headers(resp)
                # keep HTML no-store (avoid stale dashboard), allow static caching via ?v= anyway
                try:
                    ct = (resp.headers.get("Content-Type","") or "")
                    if "text/html" in ct:
                        resp.headers["Cache-Control"] = "no-store"
                except Exception:
                    pass
                return resp
        except Exception:
            pass
except Exception:
    pass
# ===================== /VSP_P0_RELEASE_IDENTITY_AND_ASSET_V1 =====================
'''
    # insert near top but after existing imports if possible
    # heuristic: after first block of imports or after shebang/comments
    lines = s.splitlines(True)
    insert_at = 0
    for i,ln in enumerate(lines[:250]):
        if ln.startswith("import ") or ln.startswith("from "):
            insert_at = i+1
    lines.insert(insert_at, block + "\n")
    s = "".join(lines)
    wsgi.write_text(s, encoding="utf-8")
else:
    print("[INFO] marker already present in WSGI")

# Patch dashboard luxe JS: poll latest run; if RID changes => reload page
js = Path("static/js/vsp_dashboard_luxe_v1.js")
jst = js.read_text(encoding="utf-8", errors="replace")
jmark = "VSP_P0_DASH_AUTO_REFRESH_RID_V1"
if jmark not in jst:
    jadd = r'''
/* ===================== VSP_P0_DASH_AUTO_REFRESH_RID_V1 ===================== */
/* Goal: after a new scan run is created, dashboard auto-detects and reloads to pick latest RID & data */
(()=> {
  if (window.__vsp_p0_dash_auto_refresh_rid_v1) return;
  window.__vsp_p0_dash_auto_refresh_rid_v1 = true;

  const API = "/api/vsp/runs?limit=1";
  let lastRid = null;
  let inFlight = false;

  async function tick(){
    if (inFlight) return;
    inFlight = true;
    try{
      const r = await fetch(API, {cache:"no-store", credentials:"same-origin"});
      if (!r.ok) return;
      const j = await r.json();
      const runs = (j && (j.runs || j.items || j.data)) || [];
      const rid = (runs[0] && (runs[0].rid || runs[0].run_id || runs[0].id)) || null;
      if (!rid) return;

      if (lastRid === null){
        lastRid = rid;
        return;
      }
      if (rid && lastRid && rid !== lastRid){
        // new run detected => reload to pick latest gate + release headers etc.
        location.reload();
      }
    }catch(e){
      // ignore
    }finally{
      inFlight = false;
    }
  }

  setInterval(tick, 12000);
  setTimeout(tick, 3000);
})();
/* ===================== /VSP_P0_DASH_AUTO_REFRESH_RID_V1 ===================== */
'''
    js.write_text(jst + "\n" + jadd + "\n", encoding="utf-8")
else:
    print("[INFO] JS auto refresh marker already present")
PY

# sanity compile
python3 -m py_compile "$WSGI" >/dev/null
echo "[OK] py_compile WSGI"

# restart
systemctl restart "$SVC" 2>/dev/null || true
sleep 0.4

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== verify vsp5 has bundle + asset_v param =="
curl -fsS "$BASE/vsp5" | grep -nE "vsp_bundle_commercial_v2|vsp_dashboard_luxe_v1" | head -n 5

echo "== verify release headers on HTML =="
curl -sS -I "$BASE/vsp5" | grep -iE "X-VSP-RELEASE-|cache-control" || true

echo "[DONE] If browser was opened before, hard refresh once (Ctrl+Shift+R). After that, new RUN should auto-reload within ~12s."
